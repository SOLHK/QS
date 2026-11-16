#import "QS.h"
#import "QSDiagnostics.h"
#import <objc/message.h>
#import <objc/runtime.h>

static Class QSGlassEffectClass;
static Class QSCornerConfigurationClass;
static const NSInteger QSRegularGlassStyle = 0;
static char QSGlassViewKey;
static char QSSelectedKey;
static NSMutableSet<NSString *> *QSStyledTargets;

void QSObserveLayout(const char *className, void (*style)(UIView *))
{
    Class viewClass = objc_lookUpClass(className);
    if (![viewClass isSubclassOfClass:UIView.class]) {
        QSLog([NSString stringWithFormat:@"layout_hook_missing=%s", className]);
        return;
    }

    SEL layout = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(viewClass, layout);
    void (*original)(UIView *, SEL) = (void (*)(UIView *, SEL))method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(UIView *view) {
        original(view, layout);
        if (object_getClass(view) == viewClass && view.window) {
            style(view);
        }
    });
    class_replaceMethod(viewClass, layout, replacement, method_getTypeEncoding(method));
    QSLog([NSString stringWithFormat:@"layout_hook_installed=%s", className]);
}

UIView *QSView(UIView *owner, const char *field)
{
    Ivar ivar = class_getInstanceVariable(object_getClass(owner), field);
    if (!ivar) {
        return nil;
    }

    // Callers name only fields verified in the supported host builds.
    id value = object_getIvar(owner, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

void QSGlass(UIView *host, UIEdgeInsets insets, CGFloat maximumRadius, BOOL selected)
{
    if (!host.window) {
        return;
    }
    CGRect frame = UIEdgeInsetsInsetRect(host.bounds, insets);
    UIVisualEffectView *glass = objc_getAssociatedObject(host, &QSGlassViewKey);
    if (CGRectIsEmpty(frame)) {
        glass.hidden = YES;
        return;
    }

    BOOL created = glass == nil;
    if (created) {
        glass = [[UIVisualEffectView alloc] initWithEffect:nil];
        glass.userInteractionEnabled = NO;
        glass.accessibilityElementsHidden = YES;

        id (*capsule)(Class, SEL, CGFloat) = (void *)objc_msgSend;
        id corners = capsule(QSCornerConfigurationClass,
                             sel_registerName("capsuleConfigurationWithMaximumRadius:"),
                             maximumRadius);
        void (*setCorners)(UIView *, SEL, id) = (void *)objc_msgSend;
        setCorners(glass, sel_registerName("setCornerConfiguration:"), corners);
        objc_setAssociatedObject(host, &QSGlassViewKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    glass.hidden = NO;
    if (!CGRectEqualToRect(glass.frame, frame)) {
        glass.frame = frame;
    }
    if (host.subviews.firstObject != glass) {
        [host insertSubview:glass atIndex:0];
    }

    NSNumber *previousSelection = objc_getAssociatedObject(glass, &QSSelectedKey);
    if (!previousSelection || previousSelection.boolValue != selected) {
        UIVisualEffect *(*makeEffect)(Class, SEL, NSInteger) = (void *)objc_msgSend;
        UIVisualEffect *effect = makeEffect(QSGlassEffectClass, sel_registerName("effectWithStyle:"), QSRegularGlassStyle);
        if (selected) {
            void (*setTintColor)(UIVisualEffect *, SEL, UIColor *) = (void *)objc_msgSend;
            setTintColor(effect, sel_registerName("setTintColor:"),
                         [UIColor colorWithWhite:1.0 alpha:0.72]);
        }
        glass.effect = effect;
        objc_setAssociatedObject(glass, &QSSelectedKey, @(selected), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (created) {
        NSString *className = NSStringFromClass(object_getClass(host));
        if (![QSStyledTargets containsObject:className]) {
            [QSStyledTargets addObject:className];
            QSLog([NSString stringWithFormat:@"glass_created=%@", className]);
        }
    }
}

void QSRemoveGlass(UIView *host)
{
    UIVisualEffectView *glass = objc_getAssociatedObject(host, &QSGlassViewKey);
    if (glass) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(host, &QSGlassViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

__attribute__((constructor))
static void QSInstall(void)
{
    @autoreleasepool {
        NSBundle *host = NSBundle.mainBundle;
        if (![host.bundleIdentifier isEqualToString:@"com.soda.music"]) {
            return;
        }
        NSString *version = [host objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [host objectForInfoDictionaryKey:@"CFBundleVersion"];
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        QSLog([NSString stringWithFormat:@"QS=1.05-test1 host=%@ build=%@ iOS=%ld.%ld.%ld",
               version, build, (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion]);

        dispatch_async(dispatch_get_main_queue(), ^{
            QSInstallDiagnostics();
            BOOL supported = ([version isEqual:@"21.6.1"] && [build isEqual:@"100216110"]) ||
                             ([version isEqual:@"21.7.0"] && [build isEqual:@"100217020"]);
            if (!supported) {
                QSLog(@"glass_skipped=unsupported_host_build");
                return;
            }
            QSInstallNetworkDiagnostics();
            if (!QSGlassRequested()) {
                QSLog(@"glass_skipped=disabled_by_user");
                return;
            }
            if (os.majorVersion < 26) {
                QSLog(@"glass_skipped=unsupported_os");
                return;
            }

            QSGlassEffectClass = objc_lookUpClass("UIGlassEffect");
            QSCornerConfigurationClass = objc_lookUpClass("UICornerConfiguration");
            if (![QSGlassEffectClass respondsToSelector:sel_registerName("effectWithStyle:")] ||
                ![QSGlassEffectClass instancesRespondToSelector:sel_registerName("setTintColor:")] ||
                ![QSCornerConfigurationClass respondsToSelector:sel_registerName("capsuleConfigurationWithMaximumRadius:")] ||
                ![UIVisualEffectView instancesRespondToSelector:sel_registerName("setCornerConfiguration:")]) {
                QSLog(@"glass_skipped=uikit_api_unavailable");
                return;
            }

            QSStyledTargets = [NSMutableSet set];
            QSInstallPlayerGlass();
            QSInstallModeGlass();
            QSLog(@"glass_hooks_ready");
        });
    }
}
