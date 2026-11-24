---
name: project-domestic-mirror
description: 国内源 dl.zephyrxiang.com/snug/ 放安装包、应用内更新与 README 媒体；看下载量；证书 2027-01-12 到期；README 结构、截图规格、GitHub 图片代理的坑
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-19T16:00:00.000Z
---

11-13 主人定：安装包要有国内源（以后官网也从这里取，GitHub Release 照留）；README 的图片、视频也放这里，用原画质。

**国内源**
- **摆法**：`https://dl.zephyrxiang.com/snug/`，和 SpeakMore 同一个桶（桶名、地域、凭据名在不进 git 的 `.machine.env`，这份记忆会公开，别写进来）。`v<版本>/` 发过不改；`latest/Snug.dmg`、`latest/update.json`（App 查更新）缓存 5 分钟、只往新版本换；`media/<名>.<指纹>.<后缀>` 放 README 媒体
- **命令**：`ship` 自动传；`mirror <版本>` 补传已公开的版本；`media <文件…>` 传媒体并打出地址。对象带 sha256 元数据，一样就跳过、不一样就拒绝
- **CDN**：防盗链关着（GitHub 图片代理才取得到）；流量上限和费用跟 SpeakMore 共用
- **下载量**（主人问了才查）：`scripts/snug stats`，口径和自测判定写在 `scripts/download_stats.py` 开头。国内源日志读 SpeakMore 的缓存：先在 SpeakMore 仓库跑一次它的 stats，`.machine.env` 的 `SPEAKMORE_STATS` 指向那个 `.stats`。报数只报 .dmg（11-19 按全部文件报过一次，多报约三成）
- **证书**：`dl.zephyrxiang.com` 免费证书 2027-01-12 到期，续期记在 SpeakMore 的记忆里；不换，两个项目的下载一起断
- 上传用的是主账号密钥，以后可换成只能写 `snug/` 前缀的子账号密钥（未做）

**README**（三种语言一起改，媒体走 `scripts/snug media`，正式 README 只引用国内源地址，图片不进 git）
- **结构**（11-18 多屏版，11-23 改）：标语统一英文 **Make Your Remote Mac Native on Any Device**（不点名哪家远控）；副标题下单列「已支持的远控」一行，配各家 App 图标（从本机装的 App 取 NSWorkspace 图标、裁透明边、192px，显示宽 40），新接一家就加一个；先「每台设备都是原生体验」（手机 → 平板 → 电脑），再「一台 Mac，所有设备」（「自定义屏幕」+「屏幕列表」），再 App 资源库、对比、安装使用、社区移植、致谢、Star 趋势。叫「屏幕」不叫「虚拟屏」；安卓按「全面支持」写；无显示器的 Mac 主人拍板照写
- 顶部原理图：主人要「像科研流程图那样讲清楚」「简洁但不是简单」，否掉了写实风和图标风。源文件没留；11-23 把连线标注从 UU Remote 改成 Remote desktop，是在原图上抹掉旧字、用 Montserrat 500 30px 重写的（字体比对吻合）
- **GitHub 简介和话题跟 README 同步改**（11-23 主人要求）：README 的定位、支持哪些远控一变，`gh repo edit -R zephyr4123/snug` 一起改
- **待换**：原生手势一节的演示动图和高清视频仍是 2.2 的，等 [[project-demo-recording]] 完成一起换
- **截图规格**：设为主屏不拍整屏，用设置页截图；MacBook 原版与 Snug 对比都裁掉顶部 33 点刘海；iPad 四边不裁；横屏手机裁掉左侧 UU 黑栏、留工具栏。17 Pro Max 原图裁成 `crop=1320:2595:0:273,pad=1320:2598:0:0:black`（ffmpeg，sips 裁不动），和旧图对齐
- **Mac 端截图**自己渲染：设置页 `.build/debug/Snug --render-settings <目录>`；欢迎页、关于页用正式版 `/Applications/Snug.app/Contents/MacOS/Snug --render-about <目录>`（调试版图标是文件夹、版本显示「开发版」）。安装一节三张都补到 1040×1096
- **GitHub 的限制**：删 `<video>`，录屏用 animated WebP、MP4 给链接；外链图片经 camo 代理，上限约 5 MiB，原样转发不压缩
- **camo 会缓存空图**（11-18）：缓存了 200、content-length 0 的响应，我们的缓存头一年 immutable，不清就一直坏。修法：从页面 HTML 找到 camo 地址，`curl -X PURGE <camo 地址>`。推完 README 要验 camo 地址取回的字节数
- **动图体积**几乎全在整屏滚动的帧上，超了用 img2webp 只降滚动段的 `-q`
- **录屏打码**：Vision `boundingBox(for:)` 按字符范围定位，只糊「用户名@机器名」那一截；逐帧复查，拿原画做对照

相关：[[project-release]]
