#import "QSDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static const NSUInteger QSResponseByteLimit = 256 * 1024;
static const NSUInteger QSFailureEntryLimit = 12;
static CFTimeInterval QSNetworkDeadline;
static Class QSHTTPResponseClass;
static NSObject *QSNetworkLock;
static NSMutableSet<NSString *> *QSNetworkEvents;
static NSMutableSet<NSString *> *QSNetworkFailures;

static void QSNetworkLogOnce(NSString *event)
{
    @synchronized (QSNetworkLock) {
        if (![QSNetworkEvents containsObject:event]) {
            [QSNetworkEvents addObject:event];
            QSLog(event);
        }
    }
}

static id QSResponseValue(id response, const char *name)
{
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(response), selector);
    if (!method || strcmp(method_getTypeEncoding(method), "@16@0:8") != 0) {
        QSNetworkLogOnce(@"network_response_getter_unavailable");
        return nil;
    }
    id (*getValue)(id, SEL) = (void *)objc_msgSend;
    return getValue(response, selector);
}

static NSString *QSCleanNetworkField(id value, NSCharacterSet *allowed, NSUInteger limit)
{
    if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > limit) {
        return @"unknown";
    }
    if ([value rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        return @"redacted";
    }
    return value;
}

static void QSObserveNetworkResponse(id response, id payload, BOOL binary, NSString *serializer)
{
    if (CACurrentMediaTime() > QSNetworkDeadline) {
        return;
    }
    QSNetworkLogOnce([@"network_serializer_hit=" stringByAppendingString:serializer]);

    id json = payload;
    if (binary) {
        if (![payload isKindOfClass:NSData.class]) {
            return;
        }
        if ([payload length] > QSResponseByteLimit) {
            QSNetworkLogOnce(@"network_body_skipped=over_262144_bytes");
            return;
        }
        json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
    }
    if (![json isKindOfClass:NSDictionary.class]) {
        return;
    }
    id status = json[@"status_code"];
    if (![status isKindOfClass:NSNumber.class] || ![status isEqualToNumber:@1000062]) {
        return;
    }

    NSURL *url = nil;
    id logID = nil;
    if ([response isKindOfClass:QSHTTPResponseClass]) {
        id candidate = QSResponseValue(response, "finalURL");
        if (![candidate isKindOfClass:NSURL.class]) {
            candidate = QSResponseValue(response, "URL");
        }
        if ([candidate isKindOfClass:NSURL.class]) {
            url = candidate;
        }
        logID = QSResponseValue(response, "logId");
    } else {
        QSNetworkLogOnce(@"network_response_metadata_unavailable");
    }

    // Keep only the endpoint and correlation ID. Never serialize the response body or headers.
    NSCharacterSet *hostCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *pathCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-~"];
    NSCharacterSet *idCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    NSString *host = QSCleanNetworkField(url.host, hostCharacters, 128);
    NSString *path = QSCleanNetworkField(url.path, pathCharacters, 192);
    NSString *correlation = QSCleanNetworkField(logID, idCharacters, 96);
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", host, path, correlation];
    @synchronized (QSNetworkLock) {
        if ([QSNetworkFailures containsObject:key]) {
            return;
        }
        if (QSNetworkFailures.count >= QSFailureEntryLimit) {
            QSNetworkLogOnce(@"network_capture_limit=12");
            return;
        }
        [QSNetworkFailures addObject:key];
        QSLog([NSString stringWithFormat:@"network_rejection status_code=1000062 host=%@ path=%@ log_id=%@",
               host, path, correlation]);
    }
}

static void QSHookResponseSerializer(const char *className, const char *selectorName, BOOL binary)
{
    Class serializerClass = objc_lookUpClass(className);
    SEL selector = sel_registerName(selectorName);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(serializerClass, &count);
    Method method = NULL;
    for (unsigned int index = 0; index < count; ++index) {
        if (method_getName(methods[index]) == selector) {
            method = methods[index];
            break;
        }
    }
    free(methods);
    if (!method || strcmp(method_getTypeEncoding(method), "@48@0:8@16@24@32^@40") != 0) {
        QSLog([NSString stringWithFormat:@"network_hook_unavailable=%s", className]);
        return;
    }

    id (*original)(id, SEL, id, id, id, id __autoreleasing *) =
        (void *)method_getImplementation(method);
    NSString *serializer = [NSString stringWithUTF8String:className];
    IMP replacement = imp_implementationWithBlock(^id(id object, id response, id payload,
                                                      id error, id __autoreleasing *resultError) {
        id result = original(object, selector, response, payload, error, resultError);
        QSObserveNetworkResponse(response, payload, binary, serializer);
        return result;
    });
    method_setImplementation(method, replacement);
    QSLog([NSString stringWithFormat:@"network_hook_installed=%s", className]);
}

void QSInstallNetworkDiagnostics(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        QSNetworkLock = [NSObject new];
        QSNetworkEvents = [NSMutableSet set];
        QSNetworkFailures = [NSMutableSet set];
        QSHTTPResponseClass = objc_lookUpClass("TTHttpResponse");
        QSNetworkDeadline = CACurrentMediaTime() + 120.0;
        QSHookResponseSerializer("TTHTTPBinaryResponseSerializerBase",
                                 "responseObjectForResponse:data:responseError:resultError:", YES);
        QSHookResponseSerializer("TTHTTPJSONResponseSerializerBaseChromium",
                                 "responseObjectForResponse:jsonObj:responseError:resultError:", NO);
        QSLog(@"network_capture_window=120_seconds");
    });
}
