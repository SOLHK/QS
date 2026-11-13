#import <UIKit/UIKit.h>

static NSString *const QSHostBundle = @"com.soda.music";
static const NSTimeInterval QSScanInterval = 0.2;
static const NSTimeInterval QSScanDuration = 6.0;

static NSHashTable<UIView *> *QSActivatedViews;
static NSTimer *QSScanTimer;
static NSTimeInterval QSScanDeadline;

static BOOL QSTrySkip(UIView *view, Class sodaButton, Class byteDanceButton)
{
    Class viewClass = view.class;
    if (view.hidden || view.alpha <= 0.01 || !view.userInteractionEnabled) {
        return NO;
    }

    if ((viewClass == sodaButton || viewClass == byteDanceButton) &&
        ![QSActivatedViews containsObject:view]) {
        UIWindow *window = view.window;
        CGRect bounds = view.bounds;
        CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
        UIView *hit = [window hitTest:[view convertPoint:center toView:window] withEvent:nil];
        if (hit == view || [hit isDescendantOfView:view]) {
            UIControl *control = [view isKindOfClass:UIControl.class] ? (UIControl *)view : nil;
            if (control && !control.enabled) {
                return NO;
            }

            UIControlEvents events = control.allControlEvents;
            if (events & UIControlEventTouchUpInside) {
                [control sendActionsForControlEvents:UIControlEventTouchUpInside];
            } else if (events & UIControlEventPrimaryActionTriggered) {
                [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
            } else if (![view accessibilityActivate]) {
                return NO;
            }

            [QSActivatedViews addObject:view];
            return YES;
        }
    }

    for (UIView *subview in view.subviews.reverseObjectEnumerator) {
        if (QSTrySkip(subview, sodaButton, byteDanceButton)) {
            return YES;
        }
    }
    return NO;
}

static BOOL QSScanWindows(void)
{
    UIApplication *application = UIApplication.sharedApplication;
    if (application.applicationState != UIApplicationStateActive) {
        return NO;
    }

    Class sodaButton = NSClassFromString(@"STAd.SplashAdSkipButton");
    Class byteDanceButton = NSClassFromString(@"BDASplashSkipButton");
    if (!sodaButton && !byteDanceButton) {
        return NO;
    }

    for (UIScene *scene in application.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            if (QSTrySkip(window, sodaButton, byteDanceButton)) {
                return YES;
            }
        }
    }
    return NO;
}

static void QSStartScan(void)
{
    QSScanDeadline = NSProcessInfo.processInfo.systemUptime + QSScanDuration;
    if (QSScanTimer) {
        return;
    }

    QSScanTimer = [NSTimer timerWithTimeInterval:QSScanInterval repeats:YES block:^(NSTimer *timer) {
        if (NSProcessInfo.processInfo.systemUptime >= QSScanDeadline || QSScanWindows()) {
            [timer invalidate];
            QSScanTimer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:QSScanTimer forMode:NSRunLoopCommonModes];
}

__attribute__((constructor)) static void QSInitialize(void)
{
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:QSHostBundle]) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            QSActivatedViews = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory |
                                                                  NSPointerFunctionsObjectPointerPersonality];
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification,
                                              UISceneDidActivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                usingBlock:^(__unused NSNotification *notification) {
                    QSStartScan();
                }];
            }
            QSStartScan();
        });
    }
}
