# QS

QS 1.02 为汽水音乐 21.6.1（构建号 100216110）的播放页和听歌模式侧栏添加系统液态玻璃。样式接入宿主控件的布局，点击、手势和选中状态由原控件处理。

需要 iOS 26 或更新版本、arm64 和兼容的 rootless 插件加载器。配置好 iPhoneOS SDK 的 [Theos](https://theos.dev/docs/installation-macos) 后，运行 `make package FINALPACKAGE=1`。生成的 `.deb` 位于 `packages/`。

材质使用 UIKit 的 `UIGlassEffect` 与 `UIVisualEffectView`。[Apple UIKit 液态玻璃示例](https://developer.apple.com/videos/play/wwdc2025/284/)
