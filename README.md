# QS

QS 1.01 是汽水音乐（`com.soda.music`）的 iOS 开屏广告跳过插件。应用进入前台后，QS 在短时间内查找已显示、可点击的原生跳过按钮，并触发按钮自身的动作。插件构建目标为 arm64，最低 iOS 15.0。`.deb` 需要兼容的 rootless 插件加载器。

在配置好 iPhoneOS SDK 的 [Theos](https://theos.dev/docs/installation-macos) 环境中执行 `make package FINALPACKAGE=1`。生成的 `.deb` 在 `packages/` 目录。

汽水音乐的 Bundle ID 来自 [Apple 应用元数据](https://itunes.apple.com/lookup?id=1605585211&country=cn)。跳过按钮类名参考 [汽水音乐规则](https://github.com/swipt-automation/official-swiplets/blob/fb69b9ee1e56aef929f3f6733ccdcb326336028f/skip-chinese-ads/src/rules.ts#L859) 和 [ByteDance SDK 规则](https://github.com/swipt-automation/official-swiplets/blob/fb69b9ee1e56aef929f3f6733ccdcb326336028f/skip-chinese-ads/src/rules.ts#L40)。
