#import "QS.h"
#import <objc/message.h>
#import <objc/runtime.h>

static Class QSGlassEffectClass;
static Class QSCornerConfigurationClass;
static const NSInteger QSRegularGlassStyle = 0;
static char QSGlassViewKey;
static char QSSelectedKey;

void QSObserveLayout(const char *className, void (*style)(UIView *))
{
    Class viewClass = objc_lookUpClass(className);
    if (![viewClass isSubclassOfClass:UIView.class]) {
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
}

UIView *QSView(UIView *owner, const char *field)
{
    Ivar ivar = class_getInstanceVariable(object_getClass(owner), field);
    if (!ivar) {
        return nil;
    }

    // Callers name only fields verified to store a strong UIKit view in 21.6.1.
    id value = object_getIvar(owner, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

void QSGlass(UIView *host, UIEdgeInsets insets, CGFloat maximumRadius, BOOL selected)
{
    if (!host) {
        return;
    }
    CGRect frame = UIEdgeInsetsInsetRect(host.bounds, insets);
    UIVisualEffectView *glass = objc_getAssociatedObject(host, &QSGlassViewKey);
    if (CGRectIsEmpty(frame)) {
        glass.hidden = YES;
        return;
    }

    if (!glass) {
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

    glass.hidden = NO;
    if (!CGRectEqualToRect(glass.frame, frame)) {
        glass.frame = frame;
    }
    if (host.subviews.firstObject != glass) {
        [host insertSubview:glass atIndex:0];
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
    NSOperatingSystemVersion minimumVersion = {26, 0, 0};
    if (![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumVersion]) {
        return;
    }

    NSBundle *host = NSBundle.mainBundle;
    if (![host.bundleIdentifier isEqualToString:@"com.soda.music"] ||
        ![[host objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"21.6.1"] ||
        ![[host objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"100216110"]) {
        return;
    }

    QSGlassEffectClass = objc_lookUpClass("UIGlassEffect");
    QSCornerConfigurationClass = objc_lookUpClass("UICornerConfiguration");
    if ([QSGlassEffectClass respondsToSelector:sel_registerName("effectWithStyle:")] &&
        [QSGlassEffectClass instancesRespondToSelector:sel_registerName("setTintColor:")] &&
        [QSCornerConfigurationClass respondsToSelector:sel_registerName("capsuleConfigurationWithMaximumRadius:")] &&
        [UIVisualEffectView instancesRespondToSelector:sel_registerName("setCornerConfiguration:")]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            QSInstallPlayerGlass();
            QSInstallModeGlass();
        });
    }
}
