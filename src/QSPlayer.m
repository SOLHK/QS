#import "QS.h"
#import "QSDiagnostics.h"
#import <objc/runtime.h>
#include <math.h>

static const char QSTabBarClass[] = "_TtC24ESTabBarController_swift8ESTabBar";
static const char QSSongTabClass[] = "_TtC6BNPlay24BNSongTabItemContentView";
static char QSSearchButtonKey;

static BOOL QSHasViewAncestor(UIView *view, const char *className)
{
    Class cls = objc_lookUpClass(className);
    for (UIView *parent = view.superview; parent && cls; parent = parent.superview) {
        if (parent.class == cls) {
            return YES;
        }
    }
    return NO;
}

static BOOL QSIsSongFeedView(UIView *view)
{
    Class cls = objc_lookUpClass("_TtC6BNPlay24BNSongFeedViewController");
    for (UIResponder *responder = view; responder && cls; responder = responder.nextResponder) {
        if (responder.class == cls) {
            return YES;
        }
    }
    return NO;
}

static void QSStyleTabBar(UIView *bar)
{
    UIView *strip = QSView(bar, "contentView");
    Class itemClass = objc_lookUpClass("_TtC24ESTabBarController_swift21ESTabBarItemContainer");
    Class songTabClass = objc_lookUpClass(QSSongTabClass);
    BOOL hasSongTab = NO;
    CGRect items = CGRectNull;
    for (UIView *item in strip.subviews) {
        if (item.class != itemClass || item.hidden) {
            continue;
        }
        for (UIView *content in item.subviews) {
            if (content.class == songTabClass) {
                hasSongTab = YES;
                break;
            }
        }
        items = CGRectUnion(items, item.frame);
    }

    CGRect frame = CGRectIntersection(strip.bounds, CGRectInset(items, -4.0, 0.0));
    if (!hasSongTab || CGRectIsEmpty(frame)) {
        QSRemoveGlass(strip);
        return;
    }
    UIEdgeInsets insets = UIEdgeInsetsMake(CGRectGetMinY(frame) - CGRectGetMinY(strip.bounds),
                                          CGRectGetMinX(frame) - CGRectGetMinX(strip.bounds),
                                          CGRectGetMaxY(strip.bounds) - CGRectGetMaxY(frame),
                                          CGRectGetMaxX(strip.bounds) - CGRectGetMaxX(frame));
    QSGlass(strip, insets, CGFLOAT_MAX, NO);
}

static void QSStyleSongTab(UIView *tab)
{
    if (!QSHasViewAncestor(tab, QSTabBarClass)) {
        return;
    }

    UIView *center = QSView(tab, "selectedView");
    if (!center.hidden && [center isDescendantOfView:tab]) {
        QSGlass(center, UIEdgeInsetsZero, CGFLOAT_MAX, NO);
    }
}

static void QSStylePlayToggle(UIView *button)
{
    if (QSIsSongFeedView(button)) {
        QSGlass(QSView(button, "backGroundView"), UIEdgeInsetsZero, CGFLOAT_MAX, NO);
    }
}

static void QSStyleModeEntry(UIView *view)
{
    if (!QSIsSongFeedView(view)) {
        return;
    }
    UIView *labelContainer = QSView(view, "$__lazy_storage_$_ydmLabelContainer");
    UIView *target = labelContainer ?: view;
    if (CGRectGetWidth(target.bounds) <= 180.0) {
        QSGlass(target, UIEdgeInsetsZero, CGFLOAT_MAX, NO);
    }
}

static void QSStyleAlternateModeEntry(UIView *view)
{
    if (QSIsSongFeedView(view)) {
        QSGlass(QSView(view, "leftContainerStackView"), UIEdgeInsetsZero, CGFLOAT_MAX, NO);
    }
}

static void QSStylePlayerAction(UIView *view)
{
    if (!QSIsSongFeedView(view) ||
        !QSHasViewAncestor(view, "_TtC6BNPlay15PlayButtonPanel")) {
        return;
    }
    QSGlass(view, UIEdgeInsetsMake(2.0, 0.0, 2.0, 0.0), CGFLOAT_MAX, NO);
}

static BOOL QSSearchLabel(NSString *label)
{
    return [label isEqualToString:@"搜索"] || [label isEqualToString:@"搜尋"] ||
           [label isEqualToString:@"Search"];
}

static void QSCollectSearch(UIView *root, UIView *frame, NSMutableArray<UIButton *> *buttons)
{
    for (UIView *view in root.subviews) {
        if (view.hidden || view.alpha <= 0.01) {
            continue;
        }
        CGRect rect = [view convertRect:view.bounds toView:frame];
        if (CGRectGetMinY(rect) > CGRectGetMinY(frame.bounds) + 145.0) {
            continue;
        }

        if (view.class == UIButton.class && [view.superview isKindOfClass:UIStackView.class]) {
            UIButton *button = (UIButton *)view;
            CGFloat side = CGRectGetWidth(button.bounds);
            CGSize imageSize = button.currentImage.size;
            // SearchComponent sets exclusive touch and a 24:32 icon-to-button ratio.
            if (button.exclusiveTouch && imageSize.width > 0.0 &&
                CGRectGetMidX(rect) > CGRectGetMidX(frame.bounds) &&
                side >= 24.0 && side <= 52.0 &&
                fabs(side - CGRectGetHeight(button.bounds)) < 1.0 &&
                fabs(imageSize.width / side - 0.75) < 0.06 &&
                fabs(imageSize.height - imageSize.width) < 1.0) {
                [buttons addObject:button];
            }
        }
        QSCollectSearch(view, frame, buttons);
    }
}

static void QSStyleSearch(UIView *frame)
{
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    QSCollectSearch(frame, frame, buttons);
    UIButton *target = buttons.count == 1 ? buttons.firstObject : nil;
    for (UIButton *button in buttons) {
        if (QSSearchLabel(button.accessibilityLabel)) {
            target = button;
            break;
        }
    }

    UIButton *previous = objc_getAssociatedObject(frame, &QSSearchButtonKey);
    if (target) {
        static dispatch_once_t foundSearch;
        dispatch_once(&foundSearch, ^{
            QSLog(@"search_target_found");
        });
    } else if (buttons.count > 1) {
        static dispatch_once_t ambiguousSearch;
        dispatch_once(&ambiguousSearch, ^{
            QSLog(@"search_target_ambiguous");
        });
    }
    if (previous != target) {
        QSRemoveGlass(previous);
        objc_setAssociatedObject(frame, &QSSearchButtonKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    QSGlass(target, UIEdgeInsetsZero, CGFLOAT_MAX, NO);
}

static BOOL QSFollowLabel(NSString *label)
{
    return [label isEqualToString:@"关注"] || [label isEqualToString:@"關注"] ||
           [label isEqualToString:@"Follow"];
}

static CGRect QSFollowFrame(id element, UIView *artist, NSUInteger depth)
{
    if (depth == 0) {
        return CGRectNull;
    }

    if (([element isKindOfClass:UIView.class] || [element isKindOfClass:UIAccessibilityElement.class]) &&
        [element isAccessibilityElement] && ([element accessibilityTraits] & UIAccessibilityTraitButton) &&
        QSFollowLabel([element accessibilityLabel])) {
        UIWindow *window = artist.window;
        CGRect rect = [window convertRect:[element accessibilityFrame] fromCoordinateSpace:window.screen.coordinateSpace];
        rect = [artist convertRect:rect fromView:window];
        if (!CGRectIsEmpty(rect) && CGRectContainsRect(CGRectInset(artist.bounds, -2.0, -2.0), rect)) {
            return CGRectIntersection(artist.bounds, rect);
        }
    }

    if ([element isKindOfClass:UIView.class]) {
        UIView *view = element;
        if (view.hidden || view.alpha <= 0.01 || [view isKindOfClass:UIVisualEffectView.class]) {
            return CGRectNull;
        }
        NSArray *children = view.accessibilityElements;
        if (children.count == 0) {
            NSInteger count = view.accessibilityElementCount;
            if (count > 0 && count <= 20) {
                for (NSInteger index = 0; index < count; ++index) {
                    CGRect rect = QSFollowFrame([view accessibilityElementAtIndex:index], artist, depth - 1);
                    if (!CGRectIsNull(rect)) {
                        return rect;
                    }
                }
            }
            children = view.subviews;
        }
        for (id child in children) {
            CGRect rect = QSFollowFrame(child, artist, depth - 1);
            if (!CGRectIsNull(rect)) {
                return rect;
            }
        }
    }
    return CGRectNull;
}

static void QSUpdateFollowGlass(UIView *artist)
{
    if (!artist.window || !QSIsSongFeedView(artist)) {
        return;
    }
    CGRect frame = QSFollowFrame(artist, artist, 8);
    if (!CGRectIsEmpty(frame)) {
        static dispatch_once_t foundFollow;
        dispatch_once(&foundFollow, ^{
            QSLog(@"follow_target_found");
        });
    }
    if (CGRectIsEmpty(frame)) {
        QSRemoveGlass(artist);
        return;
    }

    UIEdgeInsets insets = UIEdgeInsetsMake(CGRectGetMinY(frame) - CGRectGetMinY(artist.bounds),
                                          CGRectGetMinX(frame) - CGRectGetMinX(artist.bounds),
                                          CGRectGetMaxY(artist.bounds) - CGRectGetMaxY(frame),
                                          CGRectGetMaxX(artist.bounds) - CGRectGetMaxX(frame));
    QSGlass(artist, insets, CGFLOAT_MAX, NO);
}

static void QSStyleFollow(UIView *artist)
{
    static char pendingKey;
    if (objc_getAssociatedObject(artist, &pendingKey)) {
        return;
    }
    objc_setAssociatedObject(artist, &pendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *pendingArtist = artist;
    // SwiftUI may lay out its hosted views while resolving accessibility frames.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = pendingArtist;
        if (view) {
            QSUpdateFollowGlass(view);
            objc_setAssociatedObject(view, &pendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

void QSInstallPlayerGlass(void)
{
    QSObserveLayout(QSTabBarClass, QSStyleTabBar);
    QSObserveLayout(QSSongTabClass, QSStyleSongTab);
    QSObserveLayout("_TtC6BNPlay19NewTogglePlayButton", QSStylePlayToggle);
    QSObserveLayout("_TtC6BNPlay22BNPlaySongtabTitleView", QSStyleModeEntry);
    QSObserveLayout("_TtC6BNPlay15BNPlayTitleView", QSStyleAlternateModeEntry);
    QSObserveLayout("_TtC6BNPlay19BNSongFeedFrameView", QSStyleSearch);
    QSObserveLayout("_TtC6BNPlay14PlayArtistView", QSStyleFollow);
    QSObserveLayout("_TtC6BNPlay17PlayCollectButton", QSStylePlayerAction);
    QSObserveLayout("_TtC6BNPlay12BNPlayButton", QSStylePlayerAction);
    QSObserveLayout("_TtC6BNPlay18PlayMoreButtonView", QSStylePlayerAction);
}
