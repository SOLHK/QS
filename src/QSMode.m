#import "QS.h"
#import <objc/runtime.h>
#include <stdint.h>

static const char QSModeCellClassName[] = "_TtC6BNPlay14ModeSelectCell";
static Ivar QSModeSelectedField;
static void (*QSSetModeBackground)(UIView *, SEL, UIColor *);
static char QSModeSelectionKey;

static BOOL QSModeCellSelected(UIView *view)
{
    const uint8_t *storage = (__bridge const void *)view;
    return storage[ivar_getOffset(QSModeSelectedField)] != 0;
}

static void QSStyleModeCell(UIView *view)
{
    if (CGRectIsEmpty(view.bounds)) {
        return;
    }

    BOOL selected = QSModeCellSelected(view);
    NSNumber *previousSelection = objc_getAssociatedObject(view, &QSModeSelectionKey);
    if (!previousSelection || previousSelection.boolValue != selected) {
        objc_setAssociatedObject(view, &QSModeSelectionKey, @(selected), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // This view owns the original state-dependent tile fill and foreground labels.
    if (view.backgroundColor) {
        QSSetModeBackground(view, @selector(setBackgroundColor:), nil);
    }
    CGFloat radius = view.layer.cornerRadius;
    QSGlass(view, UIEdgeInsetsZero, radius > 0.0 ? radius : 12.0, selected);
}

static void QSStyleListenTogether(UIView *header)
{
    UIView *button = QSView(header, "$__lazy_storage_$_listenToButton");
    if (button) {
        QSGlass(button, UIEdgeInsetsZero, CGFLOAT_MAX, NO);
    }
}

void QSInstallModeGlass(void)
{
    Class modeCell = objc_lookUpClass(QSModeCellClassName);
    QSModeSelectedField = modeCell ? class_getInstanceVariable(modeCell, "isSelected") : NULL;
    if (QSModeSelectedField) {
        SEL setter = @selector(setBackgroundColor:);
        Method method = class_getInstanceMethod(modeCell, setter);
        QSSetModeBackground = (void (*)(UIView *, SEL, UIColor *))method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(UIView *view, UIColor *color) {
            if (object_getClass(view) != modeCell || !view.window || CGRectIsEmpty(view.bounds)) {
                QSSetModeBackground(view, setter, color);
                return;
            }

            NSNumber *previousSelection = objc_getAssociatedObject(view, &QSModeSelectionKey);
            if (view.backgroundColor) {
                QSSetModeBackground(view, setter, nil);
            }
            if (!previousSelection || previousSelection.boolValue != QSModeCellSelected(view)) {
                [view setNeedsLayout];
            }
        });
        class_replaceMethod(modeCell, setter, replacement, method_getTypeEncoding(method));
        QSObserveLayout(QSModeCellClassName, QSStyleModeCell);
    }
    QSObserveLayout("_TtC6BNPlay23ModeSelectVIPHeaderView", QSStyleListenTogether);
}
