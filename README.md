# QS

QS 1.05-test2 为汽水音乐 21.6.1（100216110）和 21.7.0（100217020）的主底栏、播放页和听歌模式侧栏添加系统液态玻璃。主底栏的每个标签按钮都有独立的玻璃背景，图标、标题、点击和选中状态由原控件处理。

此测试版用于定位导入插件后出现的“不安全”提示。21.7.0 的类与相关字段已静态核对，界面和交互仍需真机验证。当前未验证解决安全提示、恢复登录或播放。

需要 iOS 26 或更新版本、arm64 和兼容的 rootless 插件加载器。配置好 iPhoneOS SDK 的 [Theos](https://theos.dev/docs/installation-macos) 后，运行 `make package FINALPACKAGE=1`。生成的 `.deb` 位于 `packages/`。材质使用 UIKit 的 `UIGlassEffect` 与 `UIVisualEffectView`。[Apple UIKit 液态玻璃示例](https://developer.apple.com/videos/play/wwdc2025/284/)

## 日志与故障排查

QS 加载后，在汽水音乐界面双指长按约一秒可打开「QS 诊断」。入口独立于播放页，玻璃因版本不匹配或被关闭时仍可使用。

- 「导出 QS 日志」通过系统分享选单保存当前进程的诊断日志。日志记录版本、玻璃启用状态、挂接和控件命中，可在 macOS「控制台」中按 `com.solhk.qs` 筛选。 [Apple 设备诊断日志](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
- 「导入日志预览」从「文件」读取最大 64 KiB 的 UTF-8 `.log` 或 `.txt`，并在本机只读显示。
- 「下次启动禁用玻璃」会保留诊断入口。完全退出汽水音乐后重新打开，导出的日志应包含 `glass_skipped=disabled_by_user`。

测试版在启动后的 120 秒观察已核对的 TTNet 响应解析方法。对汽水域名记录业务码、HTTP 状态、传输错误与路径。不超过 256 KiB 的数据响应可读取 JSON 业务码；更大的响应标记 `over_limit`。常规状态和失败状态各保留最多 12 条去重记录。日志写入应用容器的 `Library/Caches/com.solhk.qs.log`，保留最新 120 行。可以从诊断入口导出，也可由已配对电脑读取。

响应覆盖取决于宿主实际使用的解析器；某条请求未命中观察点时，日志缺少该请求不能证明它成功。记录不包含请求头、Cookie、查询参数或完整响应体。原方法仍收到原参数，返回值与错误输出按原样传递。

验证安全提示时，对照同一版本、同一签名配置下的纯重签包与导入 QS 的包，并记录登录、播放和切歌结果。侧载安装的签名、版本和宿主校验由安装环境和汽水音乐决定。
