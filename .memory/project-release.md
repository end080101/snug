---
name: project-release
description: 发版：只走 scripts/snug；个人 Developer ID（29898YBGWD）公证；gh 绑定 zephyr4123 且写明 -R；版本号与更新日志口径；分块的应用内更新；发版后从访达重开旧版、不替主人装
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-24T16:10:21.333Z
---

- **一个入口**：构建、测试、打包、公证、发版都走 `scripts/snug`，新步骤加成子命令或内部函数，不另起脚本（主人：「通过一行命令行就能去出包、去 release，千万别散在各处」）。流程：改 VERSION 提交 → 打带说明的同名标签推上去 → `scripts/snug ship`；断了重跑只补没做完的那一步
- **Homebrew（11-24 定，12-13 主人会提醒）**：等仓库满 30 天（11-13 建仓）后给 `Homebrew/homebrew-cask` 提 PR 加 `Casks/s/snug.rb`，不先建自己的 tap。11-24 核过：自提门槛 225 星 / 90 fork / 90 关注者满足其一（当时 1436 星、114 fork）、必须过 Gatekeeper（已公证）、官方还没有叫 snug 的 cask。cask 要点：GitHub Release 的 dmg + 现成的 `.sha256`、`auto_updates true`（有应用内更新）、`depends_on macos: ">= :sonoma"`、通用包不分架构
- **签名公证**：个人 Developer ID Application（Team ID 29898YBGWD）。notarytool 档案名在 `.machine.env`，档案在数据保护钥匙串里，`security find-generic-password` 搜不到，别据此说没有。苹果回 403「A required agreement is missing」是开发者协议待签，要主人去 developer.apple.com 签
- **GitHub 账号**：`GH_CONFIG_DIR=~/.config/gh-zephyr4123`，推送和 gh 命令前 `gh api user --jq .login` 必须是 zephyr4123；gh 命令一律写 `-R zephyr4123/snug`（不写会挑 upstream，2.0.0 差点发到原作者仓库）。main 不加分支保护（11-19 主人定）
- **版本号**：x.y.0 发主打功能，x.y.z 修 issue 报的问题（带一个小入口也算）
- **更新日志**（标签说明，分 修复 / 改进 / 致谢 / 安装）：讲用户得到什么，不点名具体 App、不讲实现。主人通常只审更新日志，其余放手
- **主人的发版习惯**：合并、推送、发版前照红线先问；合并前删掉过程文档、结论并进记忆（例外：远控适配层的设计记录保留，见 [[project-remote-adapter]]）；「小补丁」不用自己手测，发版后请报告人测；**不替主人装**：从访达重开「应用程序」里的旧版（见 [[project-phone-screen]]），让它弹「软件更新」，顺带弹出的设置窗口关掉，主人自己点更新。退出主人正在跑的 Snug 要他当次点头（11-24 发 2.9.0 时自动模式拦下了），没点头就告诉他自己重开
- **发版后清理**：`dist/` 只留刚发的版本（ship 中断重跑用），更早的、`build/`、`.playwright-mcp/` 可删；`footage/`、`.build/`、`.venv/`、`.machine.env`、`design/prototype/assets/` 留着
- **应用内更新**（2.1.0 起）：按内容分块（`Snug-<版本>.pack` + `update.json`），GitHub 和国内源都传。不做差分是主人拍板的（要按版本配对、「产生一堆中间产物」），别再提。`firstUpdatable` = 2.1.0
- **本机实测更新**：别往 COS 传测试文件。临时把 `UpdateSource.tencentBase` 改成 `http://127.0.0.1:8765/snug`、VERSION 设成旧版本 install；另打新版本号的 App，用临时本地标签跑 `snug-release pack/feed` 摆成国内源目录，起支持 Range 的本地服务器。测完 `git checkout` 还原、删临时标签、重装。「立即更新」用 osascript 点 `last button of group 1 of window "软件更新"`

- **系统函数的版本坑**（11-24，#59 → 2.8.1）：打包用的 Xcode macOS 27.2 开发包把 `Date` 的 `<=`、`>=` 标成「27.2 起改调系统实现、更早用 App 自带的」，只看版本号；27.2 测试版版本号到了、系统里还没有这两个函数，一调用就崩。比较日期一律用 `timeIntervalSince`，不写 `<=`、`>=`。核对：`nm -m -arch arm64 build/Snug.app/Contents/MacOS/Snug | grep 'weak external' | grep 'from Foundation'` 只应剩 `__swift_FORCE_LOAD_$_swiftFoundation`（SwiftUI 那十几个是老版本可用的，不同类）

国内源见 [[project-domestic-mirror]]
