#import <Foundation/Foundation.h>

void QSInstallDiagnostics(void);
void QSLog(NSString *message);
NSString *QSLogSnapshot(void);
BOOL QSGlassRequested(void);
void QSSetGlassRequested(BOOL enabled);
