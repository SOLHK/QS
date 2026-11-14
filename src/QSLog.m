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
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logger = os_log_create("com.solhk.qs", "diagnostics");
        formatter = [NSISO8601DateFormatter new];
        QSLogLines = [NSMutableArray array];
    });

    os_log_with_type(logger, OS_LOG_TYPE_DEFAULT, "%{public}@", message);
    @synchronized (QSLogLines) {
        NSString *line = [NSString stringWithFormat:@"%@ %@",
                          [formatter stringFromDate:[NSDate date]], message];
        if (QSLogLines.count >= QSLogLineLimit) {
            [QSLogLines removeObjectAtIndex:0];
        }
        [QSLogLines addObject:line];
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
