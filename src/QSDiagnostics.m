#import "QSDiagnostics.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#include <string.h>

static const NSUInteger QSImportLimit = 64 * 1024;

static NSString *QSReadLog(NSURL *url, NSString **errorMessage)
{
    NSString *extension = url.pathExtension.lowercaseString;
    if (!url.isFileURL || (![extension isEqualToString:@"log"] && ![extension isEqualToString:@"txt"])) {
        *errorMessage = @"请选择 .log 或 .txt 文件。";
        return nil;
    }
    if (![url startAccessingSecurityScopedResource]) {
        *errorMessage = @"无法访问所选文件。";
        return nil;
    }

    __block NSData *data;
    [[NSFileCoordinator new] coordinateReadingItemAtURL:url options:0 error:nil
                                             byAccessor:^(NSURL *localURL) {
        NSNumber *isRegularFile;
        [localURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (isRegularFile.boolValue) {
            NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:localURL error:nil];
            NSMutableData *buffer = [NSMutableData new];
            while (buffer.length <= QSImportLimit) {
                NSError *error;
                NSData *chunk = [file readDataUpToLength:QSImportLimit + 1 - buffer.length error:&error];
                if (!chunk.length) {
                    if (!error && file) {
                        data = buffer;
                    }
                    break;
                }
                [buffer appendData:chunk];
            }
            if (buffer.length > QSImportLimit) {
                data = buffer;
            }
            [file closeAndReturnError:nil];
        }
    }];
    [url stopAccessingSecurityScopedResource];

    if (!data) {
        *errorMessage = @"无法读取所选文件。";
        return nil;
    }
    if (data.length > QSImportLimit) {
        *errorMessage = @"日志最多支持 64 KiB。";
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text || (data.length && memchr(data.bytes, 0, data.length))) {
        *errorMessage = @"请选择 UTF-8 纯文本日志。";
        return nil;
    }
    return text;
}

@interface QSDiagnosticsController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIButton *glassButton;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic) BOOL readingLog;
@end

@implementation QSDiagnosticsController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"QS 诊断";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:self action:@selector(closeMenu)];
    self.glassButton = [self buttonWithTitle:@"" action:@selector(toggleGlass)];
    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 0;
    [self updateGlassButton];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self buttonWithTitle:@"导出 QS 日志" action:@selector(exportLog:)],
        [self buttonWithTitle:@"导入日志预览" action:@selector(importLog)],
        self.glassButton, self.statusLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = title;
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)closeMenu
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateGlassButton
{
    UIButtonConfiguration *configuration = self.glassButton.configuration;
    configuration.title = QSGlassRequested() ? @"下次启动禁用玻璃" : @"下次启动启用玻璃";
    self.glassButton.configuration = configuration;
}

- (void)toggleGlass
{
    QSSetGlassRequested(!QSGlassRequested());
    [self updateGlassButton];
    self.statusLabel.text = QSGlassRequested() ?
        @"已设置为启用。完全退出并重新打开汽水音乐后生效。" :
        @"已设置为禁用。完全退出并重新打开汽水音乐后生效。";
}

- (void)exportLog:(UIButton *)sender
{
    NSString *filename = [NSString stringWithFormat:@"QS-%@.log", NSUUID.UUID.UUIDString];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    if (![QSLogSnapshot() writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        self.statusLabel.text = @"无法创建日志导出文件。";
        return;
    }

    UIActivityViewController *sheet =
        [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    sheet.completionWithItemsHandler = ^(__unused UIActivityType activity, __unused BOOL completed,
                                         __unused NSArray *items, __unused NSError *error) {
        [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    };
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)importLog
{
    if (self.readingLog) {
        return;
    }
    UTType *log = [UTType typeWithFilenameExtension:@"log"] ?: UTTypeLog;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[log, UTTypePlainText] asCopy:NO];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(__unused UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url || self.readingLog) {
        return;
    }

    self.readingLog = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error;
        NSString *text = QSReadLog(url, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            QSLog(text ? @"diagnostics_import_succeeded" : @"diagnostics_import_failed");
            QSDiagnosticsController *menu = weakSelf;
            menu.readingLog = NO;
            if (!menu || !menu.viewIfLoaded.window || menu.navigationController.topViewController != menu) {
                return;
            }
            if (text) {
                [menu showLog:text.length ? text : @"（空日志）"];
            } else {
                menu.statusLabel.text = error;
            }
        });
    });
}

- (void)documentPickerWasCancelled:(__unused UIDocumentPickerViewController *)picker
{
    QSLog(@"diagnostics_import_cancelled");
}

- (void)showLog:(NSString *)text
{
    UIViewController *preview = [UIViewController new];
    preview.title = @"日志预览";
    UITextView *reader = [UITextView new];
    reader.backgroundColor = UIColor.systemBackgroundColor;
    reader.editable = NO;
    reader.dataDetectorTypes = UIDataDetectorTypeNone;
    reader.font = [UIFontMetrics.defaultMetrics scaledFontForFont:
                   [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]];
    reader.adjustsFontForContentSizeCategory = YES;
    reader.text = text;
    preview.view = reader;
    [self.navigationController pushViewController:preview animated:YES];
}

@end

@interface QSDiagnosticsEntry : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UINavigationController *menu;
- (void)attachToWindows;
@end

@implementation QSDiagnosticsEntry

- (void)attachToWindows
{
    static char gestureKey;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow || window.windowLevel != UIWindowLevelNormal ||
                objc_getAssociatedObject(window, &gestureKey)) {
                continue;
            }
            UILongPressGestureRecognizer *gesture =
                [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(openMenu:)];
            gesture.numberOfTouchesRequired = 2;
            gesture.minimumPressDuration = 1.0;
            gesture.cancelsTouchesInView = NO;
            gesture.delaysTouchesBegan = NO;
            gesture.delaysTouchesEnded = NO;
            gesture.delegate = self;
            [window addGestureRecognizer:gesture];
            objc_setAssociatedObject(window, &gestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            QSLog(@"diagnostics_gesture_installed");
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGesture
{
    (void)gesture;
    (void)otherGesture;
    return YES;
}

- (void)openMenu:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan || self.menu) {
        return;
    }
    UIWindow *window = (UIWindow *)gesture.view;
    if (!window.isKeyWindow || window.windowScene.activationState != UISceneActivationStateForegroundActive) {
        return;
    }

    UIViewController *host = window.rootViewController;
    while (host) {
        UIViewController *next = host.presentedViewController;
        if (!next && [host isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)host).visibleViewController;
        } else if (!next && [host isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)host).selectedViewController;
        }
        if (!next || next == host) {
            break;
        }
        host = next;
    }
    if (host.viewIfLoaded.window != window || [host isKindOfClass:UIAlertController.class] ||
        [host isKindOfClass:UIDocumentPickerViewController.class] || [host isKindOfClass:UIActivityViewController.class] ||
        host.isBeingDismissed || host.isBeingPresented || host.transitionCoordinator) {
        return;
    }

    UINavigationController *menu =
        [[UINavigationController alloc] initWithRootViewController:[QSDiagnosticsController new]];
    self.menu = menu;
    [host presentViewController:menu animated:YES completion:^{
        QSLog(@"diagnostics_menu_opened");
    }];
}

@end

void QSInstallDiagnostics(void)
{
    static QSDiagnosticsEntry *entry;
    if (entry) {
        return;
    }
    entry = [QSDiagnosticsEntry new];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification,
                                      UISceneDidActivateNotification, UIWindowDidBecomeKeyNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                         usingBlock:^(__unused NSNotification *notification) {
            [entry attachToWindows];
        }];
    }
    [entry attachToWindows];
}
