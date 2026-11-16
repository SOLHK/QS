#import "QSDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static const NSUInteger QSResponseByteLimit = 256 * 1024;
static const NSUInteger QSResponseEntryLimit = 12;
static CFTimeInterval QSNetworkDeadline;
static Class QSHTTPResponseClass;
static NSObject *QSNetworkLock;
static NSMutableSet<NSString *> *QSNetworkEvents;
static NSMutableSet<NSString *> *QSNetworkResponses;
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

static NSString *QSBusinessStatus(id value)
{
    NSString *text = [value isKindOfClass:NSNumber.class] ? [value stringValue] : value;
    if (![text isKindOfClass:NSString.class] || text.length == 0 || text.length > 20) {
        return nil;
    }
    NSString *digits = [text hasPrefix:@"-"] ? [text substringFromIndex:1] : text;
    NSCharacterSet *numbers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    if (digits.length == 0 || [digits rangeOfCharacterFromSet:numbers.invertedSet].location != NSNotFound) {
        return nil;
    }
    return text;
}

static void QSObserveNetworkResponse(id response, id payload, id error, BOOL binary, NSString *serializer)
{
    if (CACurrentMediaTime() > QSNetworkDeadline) {
        return;
    }
    QSNetworkLogOnce([@"network_serializer_hit=" stringByAppendingString:serializer]);

    NSURL *url = nil;
    id logID = nil;
    NSNumber *httpStatus = nil;
    if ([response isKindOfClass:QSHTTPResponseClass]) {
        id candidate = QSResponseValue(response, "finalURL");
        if (![candidate isKindOfClass:NSURL.class]) {
            candidate = QSResponseValue(response, "URL");
        }
        if ([candidate isKindOfClass:NSURL.class]) {
            url = candidate;
        }
        logID = QSResponseValue(response, "logId");
        SEL statusSelector = @selector(statusCode);
        Method statusMethod = class_getInstanceMethod(object_getClass(response), statusSelector);
        if (statusMethod && strcmp(method_getTypeEncoding(statusMethod), "q16@0:8") == 0) {
            NSInteger (*getStatus)(id, SEL) = (void *)objc_msgSend;
            httpStatus = @(getStatus(response, statusSelector));
        } else {
            QSNetworkLogOnce(@"network_http_status_unavailable");
        }
    } else {
        QSNetworkLogOnce(@"network_response_metadata_unavailable");
    }

    NSError *transportError = [error isKindOfClass:NSError.class] ? error : nil;
    NSString *responseHost = url.host.lowercaseString;
    BOOL sodaHost = [responseHost isEqualToString:@"qishui.com"] || [responseHost hasSuffix:@".qishui.com"];
    if (!sodaHost && !transportError) {
        return;
    }

    id json = payload;
    NSString *bodyState = @"available";
    if (binary) {
        json = nil;
        if ([payload isKindOfClass:NSData.class]) {
            if ([payload length] <= QSResponseByteLimit) {
                json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
            } else {
                bodyState = @"over_limit";
                QSNetworkLogOnce(@"network_body_skipped=over_262144_bytes");
            }
        }
    }
    NSString *status = [json isKindOfClass:NSDictionary.class] ? QSBusinessStatus(json[@"status_code"]) : nil;
    if (!status && [bodyState isEqualToString:@"available"]) {
        bodyState = @"status_absent";
    }
    BOOL businessFailure = status && status.longLongValue != 0;
    BOOL failed = transportError || businessFailure || httpStatus.integerValue >= 400;
    if (!failed &&
        ![url.path hasPrefix:@"/luna/"]) {
        return;
    }

    // Keep only the endpoint and correlation ID. Never serialize the response body or headers.
    NSCharacterSet *hostCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *pathCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-~"];
    NSCharacterSet *idCharacters = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    NSString *host = sodaHost ? QSCleanNetworkField(responseHost, hostCharacters, 128) : @"unknown";
    NSString *path = sodaHost ? QSCleanNetworkField(url.path, pathCharacters, 192) : @"unknown";
    NSString *correlation = sodaHost ? QSCleanNetworkField(logID, idCharacters, 96) : @"unknown";
    NSString *errorDomain = transportError ? QSCleanNetworkField(transportError.domain, hostCharacters, 128) : @"none";
    NSString *errorCode = transportError ? [NSString stringWithFormat:@"%ld", (long)transportError.code] : @"none";
    NSString *http = httpStatus ? httpStatus.stringValue : @"unknown";
    NSString *business = status ?: @"unknown";
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@", host, path, http, business,
                     errorDomain, errorCode];
    @synchronized (QSNetworkLock) {
        NSMutableSet<NSString *> *records = failed ? QSNetworkFailures : QSNetworkResponses;
        if ([records containsObject:key]) {
            return;
        }
        if (records.count >= QSResponseEntryLimit) {
            QSNetworkLogOnce(failed ? @"network_failure_limit=12" : @"network_response_limit=12");
            return;
        }
        [records addObject:key];
        QSLog([NSString stringWithFormat:@"network_response host=%@ path=%@ http_status=%@ status_code=%@ error_domain=%@ error_code=%@ body=%@ log_id=%@",
               host, path, http, business, errorDomain, errorCode, bodyState, correlation]);
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
        // Read the failure result only after the original serializer has completed.
        id observedError = error;
        if (!result && resultError && [*resultError isKindOfClass:NSError.class]) {
            observedError = *resultError;
        }
        QSObserveNetworkResponse(response, payload, observedError, binary, serializer);
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
        QSNetworkResponses = [NSMutableSet set];
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
