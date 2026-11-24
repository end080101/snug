# 设计

Snug 界面的设计令牌和原型。界面以这里的原型为准，产品定位见 [docs/PRODUCT.md](../docs/PRODUCT.md)。

```
design/
  design-tokens.json      设计令牌：字号、颜色、间距、圆角、尺寸、动效的唯一来源
  tokens-to-css.mjs       把令牌转成原型用的 CSS 变量
  prototype/
    index.html            界面原型：Mac 上（菜单栏、设置三页、添加屏幕、屏幕详情、关于、电脑屏的小竖条与 App 资源库浮层）
                          和 Snug 屏上（手机竖屏、手机横屏、平板横屏）
    prototype.css         原型的样式，数值全部取 tokens.css 的变量
    tokens.css            生成的，不要手改
    export-assets.swift   从本机导出原型要用的 SF Symbols 和 App 图标
    snapshot.swift        用 WebKit（Safari 的内核）直接打开原型截图，检查 Safari 里的样子
    assets/               导出的图标和内嵌图标的 symbols.css（不进 git：苹果的图标不随仓库分发）
```

## 打开原型

```bash
swift design/prototype/export-assets.swift   # 第一次，或者加了新图标之后
open design/prototype/index.html
```

右上角可以切浅色、深色。原型的状态是 2026-11-17 主人确认过的版本，界面以它为准。

检查改动时用 Safari 的内核截图，别只用 Chrome 加本地服务器（Safari 直接打开本地文件时有自己的限制，比如 CSS 遮罩读不了本地图片）：

```bash
swiftc -O -o /tmp/snapshot design/prototype/snapshot.swift
/tmp/snapshot design/prototype/index.html /tmp/proto.png 1500        # 加 dark 截深色
```

## 改令牌

只改 `design-tokens.json`，改完重新生成原型的 CSS 和 App 的 Swift 常量：

```bash
node design/tokens-to-css.mjs
SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests
```

令牌分两套：`mac` 管 Mac 上的界面，`touch` 管手机和平板屏上的面板。带 `system` 的颜色在 Swift 里用对应的系统语义色（再带 `alpha` 的是这个系统色按深浅外观加透明度），`light` / `dark` 只给原型预览用。

App 里的取值都来自生成的 `Sources/Snug/UI/DesignTokens.swift`（`MacTokens`、`TouchTokens`、`MotionTokens`），不手改；`DesignTokensTests` 校验它和 `design-tokens.json` 一致，忘了重新生成测试就过不了。界面改完用 `--render-<界面>` 渲染出来和原型对照（见 [docs/development.md](../docs/development.md#启动参数)）。
