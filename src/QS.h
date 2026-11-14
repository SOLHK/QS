#import <UIKit/UIKit.h>

void QSObserveLayout(const char *className, void (*style)(UIView *));
UIView *QSView(UIView *owner, const char *field);
void QSGlass(UIView *host, UIEdgeInsets insets, CGFloat maximumRadius, BOOL selected);
void QSRemoveGlass(UIView *host);
void QSInstallPlayerGlass(void);
void QSInstallModeGlass(void);
