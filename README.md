# QS

QS 1.03 为汽水音乐 21.6.1（构建号 100216110）的播放页和听歌模式侧栏添加系统液态玻璃。样式接入宿主控件的布局，点击、手势和选中状态由原控件处理。

需要 iOS 26 或更新版本、arm64 和兼容的 rootless 插件加载器。配置好 iPhoneOS SDK 的 [Theos](https://theos.dev/docs/installation-macos) 后，运行 `make package FINALPACKAGE=1`。生成的 `.deb` 位于 `packages/`。材质使用 UIKit 的 `UIGlassEffect` 与 `UIVisualEffectView`。[Apple UIKit 液态玻璃示例](https://developer.apple.com/videos/play/wwdc2025/284/)

## 日志与故障排查

QS 加载后，在汽水音乐界面双指长按约一秒可打开「QS 诊断」。入口独立于播放页，玻璃因版本不匹配或被关闭时仍可使用。

- 「导出 QS 日志」通过系统分享选单保存当前进程的诊断日志。日志记录版本、玻璃启用状态、挂接和控件命中，可在 macOS「控制台」中按 `com.solhk.qs` 筛选。 [Apple 设备诊断日志](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
- 「导入日志预览」从「文件」读取最大 64 KiB 的 UTF-8 `.log` 或 `.txt`，并在本机只读显示。
- 「下次启动禁用玻璃」会保留诊断入口。完全退出汽水音乐后重新打开，导出的日志应包含 `glass_skipped=disabled_by_user`。

遇到宿主提示版本不安全时，先在未加载 QS 的 App Store 原版上验证登录。侧载安装的签名、版本和宿主校验由安装环境和汽水音乐决定。
