#import "QSDiagnostics.h"
#import <os/log.h>

static NSString *const QSDisableGlassKey = @"com.solhk.qs.glass-disabled";
static const NSUInteger QSLogLineLimit = 120;
static NSMutableArray<NSString *> *QSLogLines;

BOOL QSGlassRequested(void)
{
    return ![NSUserDefaults.standardUserDefaults boolForKey:QSDisableGlassKey];
}

void QSSetGlassRequested(BOOL enabled)
{
    [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:QSDisableGlassKey];
    QSLog(enabled ? @"glass_preference=enabled_next_launch" : @"glass_preference=disabled_next_launch");
}

void QSLog(NSString *message)
{
    static os_log_t logger;
    static NSISO8601DateFormatter *formatter;
    static NSURL *logURL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logger = os_log_create("com.solhk.qs", "diagnostics");
        formatter = [NSISO8601DateFormatter new];
        QSLogLines = [NSMutableArray array];
        NSError *error;
        NSURL *cacheURL = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory
                                                              inDomain:NSUserDomainMask
                                                     appropriateForURL:nil
                                                                create:YES
                                                                 error:&error];
        logURL = [cacheURL URLByAppendingPathComponent:@"com.solhk.qs.log"];
        if (!logURL) {
            os_log_with_type(logger, OS_LOG_TYPE_ERROR,
                             "diagnostics_cache_unavailable domain=%{public}@ code=%ld",
                             error.domain, (long)error.code);
        }
    });

    os_log_with_type(logger, OS_LOG_TYPE_DEFAULT, "%{public}@", message);
    @synchronized (QSLogLines) {
        NSString *line = [NSString stringWithFormat:@"%@ %@",
                          [formatter stringFromDate:[NSDate date]], message];
        if (QSLogLines.count >= QSLogLineLimit) {
            [QSLogLines removeObjectAtIndex:0];
        }
        [QSLogLines addObject:line];
        if (logURL) {
            NSString *snapshot = [NSString stringWithFormat:@"QS diagnostics\n%@\n",
                                  [QSLogLines componentsJoinedByString:@"\n"]];
            NSError *error;
            if (![snapshot writeToURL:logURL atomically:YES
                             encoding:NSUTF8StringEncoding error:&error]) {
                os_log_with_type(logger, OS_LOG_TYPE_ERROR,
                                 "diagnostics_write_failed domain=%{public}@ code=%ld",
                                 error.domain, (long)error.code);
            }
        }
    }
}

NSString *QSLogSnapshot(void)
{
    NSMutableArray<NSString *> *lines = QSLogLines;
    if (!lines) {
        return @"QS diagnostics\n";
    }
    @synchronized (lines) {
        return [NSString stringWithFormat:@"QS diagnostics\n%@\n",
                [lines componentsJoinedByString:@"\n"]];
    }
}
