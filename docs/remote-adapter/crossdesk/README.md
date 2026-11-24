# CrossDesk 适配：上下文与计划

> 状态（2026-11-23）：第 7 节 1–13 步已落地，crossdesk-cli 本机实测（8.1）和一轮多维审查已修完；待手机实测（第 8 节 B3–B5、B7、B9、A1、A4，UU 回归 B1、B2）和门面一轮。工作分支：本地 `pr58-crossdesk`，推到 PR #58 的来源分支 `nexmoe/snug:crossdesk-adapter`。
> 本文是这次适配的唯一上下文入口：开工前先读；结论变了就改这里，别让它过期。
> 行号默认指 CrossDesk `v1.7.6-20261112`（`5f526cd`）；主干指 `mcp` 分支 `acf678d`（11-23）。

## 1. 已定的事

| 日期 | 决定 |
| :--- | :--- |
| 11-23 | PR #58（作者 nexmoe）一定要合。我们直接在他的分支上追加提交修改，不退回作者；作者已表示「这个分支交给你」 |
| 11-23 | 先把内核打通、实测过，README、界面文案、对外措辞这些门面最后统一改 |
| 11-23 | **手势必须做**：CrossDesk 在 Snug 手机、平板屏上要有和 UU 一样的原生手势：单指滑滚动带惯性、长按选择、长按松手右键、点关闭按钮先归位再关。不接受「保留 CrossDesk 自己的手势、Snug 只补一点」 |
| 11-23 | 原生手势的前提：手机端选「绝对鼠标」。默认的「相对鼠标」只发光标位移、不发手指位置，谁都翻译不了；Snug 认出后提示用户切换 |
| 11-23 | 「提前准备虚拟屏」保留：只在装了「只在启动时认显示器」的远控时显示；打开前像「设为主屏」那样弹确认，讲清代价 |
| 11-23 | 给 CrossDesk 上游开 issue：先肯定项目（免费、开源、质量好），说明 Snug 在适配，再请它支持「显示器变化后重新识别」。已发 [kunkundi/crossdesk#200](https://github.com/kunkundi/crossdesk/issues/200) |
| 11-23 | 只在启动时认屏的远控远程中，常驻的屏（提前准备的、设为主屏的）在手机上「退出」只还原窗口、屏留着：撤了远程结束又建回来会换编号，CrossDesk 就选不到了。回 Mac 原来的画面靠在 CrossDesk 里切屏，没接显示器的 Mac（issue #8）也一样。不求既要又要，做到 UU 的八九成就好。README「退出这块屏」「未接显示器的 Mac」两行留门面一轮改 |

已对外说明（11-23）：README 三种语言顶部「正在全力接入 CrossDesk」（main `b74fb1f`）；#33、#35、#47、#55、讨论区 #51、PR #58 已回复进展。PR 回复里写了「让 CrossDesk 也用上单指滚动等手势」，与上面的决定一致。

## 2. CrossDesk 概况

- `kunkundi/crossdesk`，GPL-3.0-only，C++。被控端 Windows、macOS、Linux；控制端 iOS（App Store）、安卓（APK）、鸿蒙、桌面、网页、CLI；可自建服务器；大约每周发版。
- **只读不拷**：GPL 约束复制和分发，不约束阅读。CrossDesk 的代码一行都不进 Snug。
- 主人的真机：Mac 装 v1.7.6（`/Applications/CrossDesk.app`，bundle `cn.crossdesk.app`，Team `RJZC936RL7`），iPhone 装 App Store 版。

## 3. CrossDesk 的行为（读源码 + 真机核实）

### 3.1 显示器

- **只在启动时认一次**：抓屏器初始化时枚举显示器（`screen_capturer_sck_impl.mm` `Init`，约 333–400 行）；视频通道按当时的屏数一次性注册（`gui_runtime.cpp:386-392`，主干 `:393-399`）。之后加的屏，控制端选不到。
- 空闲时显示器变化直接忽略（`sck_impl.mm:876`），抓屏中只更新已有槽位。
- 编号对不上时按位置回退（`sck_impl.mm:560-617`）：开始抓屏时先按这一格记的 displayID 找，找不到就取系统此刻屏幕列表（ScreenCaptureKit 的顺序）里同一序号的那块，再把这一格改记成它。Snug 每次重建屏都会换 displayID（11-23 本机：Snug 重启 #22 → #23，开关「提前准备」#21 → #22），屏数不变、新屏排在原来的序号上时 CrossDesk 照样推得到。**未验证**，见实测 B8。
  - ScreenCaptureKit 的顺序：11-23 本机四次 CrossDesk 启动（含 crossdesk-cli 实测的两次），Snug 的屏都排第 0，实体屏在后。CrossDesk 连上先推第 0 块，所以 Snug 的屏在它启动前就在时，一连上就是 Snug 的屏（四份样本，**未验证**是否总这样）。
  - ✅ 11-23 用 crossdesk-cli 连回本机实测（B8）：Snug 重启 #24 → #25 后连第 0 格，CrossDesk 日志 `display mapping refreshed: slot=0, old_id=24, new_id=25`，推的正是新的 Snug 屏。
  - 所以 Snug 判「CrossDesk 选不到某块屏」按格子推算（`CrossDeskSlots.unreachable`）：每格推哪块屏从日志跟着读（启动时 `display discovered` 是初值，之后每句 `display mapping refreshed` 改一格）；格子推的屏还在线的都选得到；新屏不多于推着已下线屏的格也选得到；多了一律算选不到（哪块落哪格看系统排序，宁可多报）。
  - 格子会被改走：推着 Snug 屏时 Snug 把屏撤了，CrossDesk 抓屏报错（-3815）后约 2 秒自动恢复，那格改推内建屏（`slot=0, old_id=27, new_id=1`），控制端列表里出现两个「Built-in Retina Display」；之后 Snug 再建的屏没格子，要重启 CrossDesk（B14 实测）。
- **开机顺序**：CrossDesk 比 Snug 的屏先起来，手机就只看到实体屏，重启 CrossDesk 才能选到（nexmoe 11-23 真机复现）。CrossDesk 启动后 0.21 秒就枚举完，Snug 建屏要 1.6 秒。
- **每次连接都要重新选屏**：最后一台控制端断开后，被控端把选中的屏重置成 0 号（`session_device_manager.cpp:866`）；iOS 断开时也重置（`RemoteSessionModel.swift:739`）。
- 控制端能改被控屏的分辨率（`display_resolution_mac.h:145-174`），最后一台断开时恢复。改到 Snug 的屏上会和 Snug 抢，**未实测**。

### 3.2 隐私屏与锁屏

- 默认开隐私屏、断开即锁屏（`config_center.cpp:155-160`）。
- **屏数或任一屏的尺寸一变，隐私屏就判失效、撤掉遮罩，本机画面露出来**（`privacy_backend_mac.mm:121-134`）。主人第一次连接时，它就因为有窗口挡住遮罩失效过一次。
- 遮罩在 `kCGScreenSaverWindowLevel + 1`，不接鼠标（`:79-98`、`:249`），会盖住每块屏，包括 Snug 的屏。Snug 核对关闭按钮时取最前面的窗口（`TouchTap.onScreen`），可能取到遮罩，导致拦截退化成普通点击。**推断，未验证**。
- 断开后 4–10 毫秒锁屏（11-23 绝对鼠标那次连接迟了 9.5 秒，原因未查）。Snug 的会话收尾要等 1.5 秒去抖加 15 秒重连窗口，所以一定发生在锁屏之后；锁屏时辅助功能读不到窗口。

### 3.3 输入

- **线上只有鼠标**：`{x, y, s, flag}`，flag 共 9 种，x、y 是选中屏内的归一化坐标，**没有控制端平台字段**（`libs/wire/include/remote_action.h:41-61`）。宿主虽然收到了平台和设备名，但只用 `LOG_DEBUG` 记（`peer_data_callbacks.cpp:528,558`），发布版日志里没有。所以 Snug 分不出连进来的是 iPhone 还是安卓。
- **Mac 上的注入**：CrossDesk 主进程 `CGEventPost(kCGHIDEventTap)`，每个事件带 `kCGEventSourceUserData = 0x43524f5353444553`，即 "CROSSDES"（`mac_injected_event.h:14`、`mouse_controller.cpp:165-243`）：
  - 左键按着时，move 变成 LeftMouseDragged；
  - clickState 由它自己按 500ms、8px 计算，上限 3；
  - 滚轮用 `kCGScrollEventUnitLine`，s 直接当行数，不设 continuous 和 phase（`:214-221`）；
  - 断开或队列溢出时，补发按着的键的抬起（`:53-78`）。
- 被控端由独立 worker 线程分发：队尾是同一控制端的 move 时，新 move 直接替换它；每个控制端最多排 128 条（`remote_input_dispatcher.cpp:41-63,280-344`、`.h:43`）。
- iOS 的移动、按键、滚轮都走可靠有序流（`CrossDeskRTCBridge.mm:880-906`）。
- **手机端默认「相对鼠标」**：iOS `RemoteSessionModel.swift:32-37`，安卓 `MainActivity.java:341`。设置里的三个选项是「收起鼠标、绝对鼠标、相对鼠标」。

iOS 方言（`RemoteTouchInputView.swift:160-196,299-371,422-462,492-546`；`RemoteMouseInput.swift:34-48`）：

| 手势 | 相对鼠标（默认） | 绝对鼠标 |
| :--- | :--- | :--- |
| 单指点 | 在**光标处**发 move、左键按下、抬起 | 在**手指处**发 move、按下、抬起（同一毫秒内） |
| 单指滑 | 只发 move，挪光标（位移 ×1.35） | 只发 move，坐标就是手指位置；**开始和结束都没有信号** |
| 长按 0.35 秒（允许移动 14pt） | 光标处 move、左键按下，之后是拖动，松手抬起 | 手指处，其余同左 |
| 双指点 | 右键按下、抬起 | 同左 |
| 双指滑 | 画面原始大小且没认成捏合时，每 12pt 发一个 ±1 行滚轮；否则平移手机上的画面 | 同左 |
| 捏合 | 放大手机上的画面 | 同左 |
| 虚拟鼠标条 | 左右键按下、抬起，**前面不带 move** | 同左 |

安卓绝对模式（`RemoteVideoView.java:61-74,198-225`）：单指拖发左键按下、拖动、抬起，和 UU 同形；长按由客户端发右键；双指滑每 16dp 发 ±1 行，方向和 iOS 相反。鸿蒙同安卓（只抽查过）。

**「不丝滑」**：事件成团到达。4K 外接屏上团周期中位 81ms，偶尔停 0.7–1.1 秒；内建屏中位 15ms，基本不成团。被控端是收到就分发，不是它在批处理；卡在哪一段还没查。

### 3.4 会话信号

- 日志 `~/Library/Logs/CrossDesk/crossdesk.log`，spdlog 轮转，5MB × (1+3) 份（`rd_log.cpp:75-76`）。格式 `[yyyy-MM-dd HH:mm:ss.SSS] [crossdesk] [级别] [文件:行] 内容`，本地时间。
- PR 依赖的句子两版都在：
  - `Logger initialized`（`rd_log.cpp:93`，主干 `:111`）
  - `Start screen capturer, show cursor: …`（`session_device_manager.cpp:345`，主干 `:346`）
  - `Start screen capturer failed: …`（`:350`，主干 `:354`）
  - `Stop screen capturer`（`:357`，主干 `:361`）
  - `Last remote controller disconnected; …`（`connection_runtime.cpp:235`，主干 `:245`）
- **电源断言**「CrossDesk is sharing the desktop」：抓屏开始且有控制端时建两条（PreventUserIdleSystemSleep、PreventUserIdleDisplaySleep），停止抓屏时释放（`screen_sharing_power.cpp:96-108,233-243`；`session_device_manager.cpp:320-325,346`）。11-23 实测：
  - 09:03:53.951 开始抓屏，09:03:54 起 `pmset -g assertions` 就能看到，空闲时没有；
  - 09:10:08.951 最后一台断开，09:10:18.480 停止抓屏，断言随之消失：**比断开晚了 9.5 秒**。
  - 用断言判在场能避开日志轮转、时区、删日志、改措辞这些问题，查一次 0.13ms；代价是断开可能晚几秒才看到。
- **进程**：经访达启动的 CrossDesk 有 `launchDate`。开机自启写的是 LaunchAgent、直接拉可执行文件（`autostart.cpp:30-57`），看门狗用 `execv` 重启（`runtime_daemon.mm:175-186`），这两种拉起的 `launchDate` 都是 nil（同构探针实测；系统拉起的访达、程序坞也是 nil）。
- 能用来核对「CrossDesk 有没有看到 Snug 屏」的日志：启动时 `macOS display discovered: index=…, display_id=…, name=…`；每次连接 `Local display [i:name]`。
- DeskHub 预览墙也会抓屏，可能被当成远程（链路没读完）。

## 4. 真机录制

主人的 iPhone（App Store 版）连 Mac 实体屏，不是 Snug 的屏。工具 `recordings/crossdesk_events.swift`：只听不改，只记带 CROSSDES 标记的鼠标事件；第二份起每行带 `ts=`（CGEvent 时间戳）。两份录制是回放测试的夹具，放在 `Tests/Remotes/CrossDesk/Fixtures/`。

### 4.1 相对鼠标：`ios-1.7.6-relative.log`（878 个事件）

- 单指滑：只有 move，每段第一个点等于上一段光标停的位置。
- 点按 10 次：move、按下、抬起，从按下到抬起不超过 8ms。
- 长按拖 3 次：按下后 0.648、0.800、0.772 秒才拖出 10pt，离 Snug 判「选择」的 0.5 秒门槛只多 0.15–0.3 秒。
- 双指滑：0 个滚轮事件。主人确认手机上是整个画面在平移。

### 4.2 绝对鼠标：`ios-1.7.6-absolute.log`（815 个事件）

- 单指滑：只有 move，坐标直接跳到手指处，开始和结束都没有信号。
- 相邻 move 的间隔：
  - 小于 50ms 的 534 次，位移中位 7px；50–100ms 的 42 次；
  - 100–275ms 的 16 次，位移都小（最大一次 222ms 移了 73px）；
  - 297ms 及以上的，多数是下一下手势：起点跳了 141–759px；另有 3 次位移 0px（手指停住，或下一下落在原处）。
  - 由此推断：「停约 0.3 秒，或者位置大跳」可以判作松手。参数要看手感再定。
- 点按：move、按下、抬起，同一毫秒到 8ms 内到齐。
- 长按不动松手：按下，0.84 秒后抬起（2 次）。
- 长按后拖：按下、95 个拖动、抬起；另有 2 次按下约 1.2 秒后才小幅拖。
- 双指点：右键按下、抬起，相隔 92ms。
- 双指滑（画面原始大小）：37 个滚轮，每个 ±1 行，间隔中位 63ms。

## 5. PR #58 现状与核实过的问题

PR 一个提交 `28e1ae5`，31 个文件，+480 −46；`scripts/snug check` 原样全过（Swift 485 项，Python 15 项）。做了这些：
- CrossDesk 适配器：读日志判连接；
- 「提前准备虚拟屏」开关；
- `injector` 改成可选，CrossDesk 传 nil，即不走 Snug 的手势翻译；
- 会话结束时，留下的屏把窗口归位；
- `remote-check crossdesk` 诊断；
- 文档和 README（门面，待定）。

下面每条都经过源码核对或实验重跑（实验 E1–E5：同一组测试分别在 main 和 PR 的副本上跑）：

| # | 问题 | 证据 |
| :--- | :--- | :--- |
| 1 | 会话结束后马上又连上，上一次的提示和监视会残留；**只装 UU、默认设置也会** | `DeskSet.endSession` 循环里的 `return` 跳过了 `setNotice(nil)` 和 `forgetSession()`；E1：main 通过，PR 失败 |
| 2 | 开机自启或看门狗拉起的 CrossDesk 认不出 | `CrossDeskRemoteAdapter.swift:27,55-58` 滤掉了 launchDate 为 nil 的进程，见 3.4 |
| 3 | 日志判定拿本地时间字符串逐字比较：夏令时回拨那一小时漏判；找不到那几句时每拍整份重扫，4×5MB 一次 365ms（正常 0.3ms） | `CrossDeskLogs.swift:60-65`、`CrossDeskLog.swift:17-24`；重跑基准 |
| 4 | 适配器自己一条日志都不写，3 处 `try?` 吞掉错误（连入、断开由核心记） | grep `Sources/Remotes/CrossDesk` |
| 5 | `remote-check crossdesk`：日志改版时只打一行 ℹ️，退出码 0；只读当前 Snug.log | `CrossDeskDiagnostics.swift:22-40`；UU 的版本还会读 `.1` |
| 6 | `injector` 改可选：CrossDesk 没有手势翻译，与「手势必须做」冲突，也丢了关闭按钮拦截 | `RemoteAdapter.swift:13-16`、`CrossDeskRemote.swift:7`、`AppController.swift:52` |
| 7 | 「提前准备」打开时：<br>· 放不回去的窗口丢了记录，屏上显示空的资源库（E4）<br>· 用户自己开的窗口留在看不见的屏上（E3）<br>· 远程中撤过屏后永久配置不写，每 2 秒空跑一次 settle（E2）<br>· 空闲时指针能滑进看不见的屏（#29 的保护只在重连等待期生效） | `Desk.vacate` 丢掉 `putBack` 的结果；`ScreenSet.isResident` 只认主屏；`AppController.swift:174-180` |
| 8 | 默认（「提前准备」关）时，连上后才建的屏 CrossDesk 选不到，还会让隐私屏失效 | 3.1、3.2 |
| 9 | 设置页写死了 CrossDesk、UU 的名字（门禁不扫 App 层）；开关对只装 UU 的用户也生效 | `SettingsWindow.swift:60,285`；`ScreenPlan.swift:16` |
| 10 | 小问题若干：<br>· 英文注释，命名 `CrossDeskLog` 和 `CrossDeskLogs` 只差一个 s<br>· `RemoteCrossDeskSystem` 对 `SnugSystem` 的依赖没用到<br>· `ScreenPlanTests.swift:39` 测试名和内容不符<br>· 删掉重连守卫、或删掉 matchWidth，测试照样全绿（变异实验）<br>· `--preview-screens` 的行为变了（E5） | 核实报告 |

文档里的事实错误（`docs/remotes/crossdesk.md:3`「CrossDesk 处理自己的点按、拖动、滚动」等），技术部分随代码同步，措辞放到门面那一轮。

## 6. 手势方案（按 11-23 的决定修订）

目标：CrossDesk 在 Snug 手机、平板屏上的手感和 UU 一样。

### 6.1 结构

沿用合成方案，以 12.4 草案的「各家整理 + 共用翻译」为准：

- **端口**：`PointerEvent`（核心中性的原始事件）、`TouchNormalizer` 协议（各家整理，纯值类型、可单测）、`DirectTouch`（UU 直通）、`TouchPipeline`（纯值的分派，可测，顺带还掉设计记录 7.5「TouchTap 的分派没有测试」）。
- **身份**：`RemoteIdentity.injector` 改回必填（main 的形状），另加 `normalizer`，默认 `DirectTouch`。按 main 写的 fork 照样能编译，行为不变。
- **协议用扩展形态**，因为 CrossDesk 需要合成手势：
  - `normalize` 返回 `before` 和 `current`，可以在当前事件前补输入；
  - 加 `deadline` 和 `tick(at:)`，由监听线程的计时器喂超时拍，用来收尾；
  - 加 `consumes`，把 mouseMoved 加进掩码。
- **只登记 UU 时，行为和日志逐字不变**。先把 UU 现在的手势现状做成固定测试（黄金母本），再动翻译器。

### 6.2 CrossDesk 的整理

- **单指滑（绝对鼠标）**：不按键的 move 序列合成手指的按下、拖动、抬起。停 T 秒（约 0.3 秒）或位置大跳就收尾，交翻译器，得到带惯性的滚动。
- **点按**：move、按下、抬起在同一团里到齐，交翻译器当一次点击。关闭按钮拦截、惯性中点按停住都照常。
- **长按**：iOS 客户端只在两种时候发左键按下：点按结束时，和长按成立时。所以按下后同一团里没跟着抬起，就是长按。告诉翻译器「已经按住够久」，之后拖动是选择，松手是右键，和 UU 一致。**待用数据钉住**。
- **虚拟鼠标条**：按下前没有同一位置的 move，就原样放行。**假设**，要录一段虚拟鼠标条验证。
- **双指点**：右键，原样放行。
- **双指滑**：±1 行的滚轮可以翻成顺滑的像素滚动。次要，可以后做。
- **相对鼠标**：拿不到手指位置，不翻译，提示用户切「绝对鼠标」。怎么认出来（比如每段第一个点等于上次光标位置）**待定**。
- **安卓（绝对）**：本来就是按下、拖动、抬起，直通即可；长按的右键由客户端发。整理按事件形状区分：不按键的 move 序列是 iOS，按下后马上拖是安卓。**没有安卓录制**。

待定的参数和风险：
- 收尾时长 T、大跳阈值、长按的判定窗口；
- 事件成团会让滚动一顿一顿（可能要匀开，会加延迟，要测）；
- mouseMoved 进掩码后，全机的鼠标移动都要经过监听，开销要测；
- 怎么认相对鼠标。

**被推翻的做法（别走回头路）**：
- 把按下时间统一往前推 0.35 秒：虚拟鼠标键按 0.2 秒松开会被判成右键；
- 把 CrossDesk 直接当手指（不整理）：长按后快拖会判成滚动，长按松手会多出右键；
- 只保留 CrossDesk 自己的手势、Snug 只补关闭按钮：主人否决。

### 6.3 实现状态（11-23）

已按 6.1 落地（`be09f95`…`52485c3`）。CrossDesk 的整理在 `Sources/Remotes/CrossDesk/Logic/CrossDeskTouch.swift`，参数都拿两份真机录制（`Tests/Remotes/CrossDesk/Fixtures/`）钉住：

| 参数 | 值 | 依据 |
| :--- | :--- | :--- |
| 点按的移动与按下的间隔 `touchMoveLead` | 20ms 内、同一点 | 13/13 在 2ms 内到齐；超出即虚拟鼠标键，原样放行 |
| 长按 `holdAfterDown` | 按下后 0.15 秒没抬起 | Snug 0.5 秒减客户端已等的 0.35 秒 |
| 单指滑收尾 `slideEnd` | 停 0.3 秒 | 滑动中停顿最长 0.275 秒，下一下最快隔 0.296 秒 |
| 手指落到别处 `landingGap` / `landingJump` | 隔 ≥ 0.15 秒且跳 ≥ 80 点 | 成团时滑动中会隔 60–100ms 跳一大步（最大 85 点）；隔 0.15 秒以上的单步最大 73 点 |
| 停顿后的移动先扣一下 `pauseGap` | 停 ≥ 60ms | 可能是点按的移动，扣 20ms 看是不是跟着同一点的按下 |
| 认相对鼠标 | 点按、长按之后，下一下的开头连续 3 次落在抬起那一点；中间有一下挪开就重新数 | 绝对鼠标原地再点偶尔也会这样；滑动中按住不动再接着滑，开头也在原处，和相对鼠标分不出，不算。代价：只滑不点的相对鼠标用户要点过几下才收到提醒（相对鼠标录制晚约 4 秒认出）。认出后手机屏顶上提醒切「绝对鼠标」（`cf01cf2`） |

回放结果（超时拍准点、惯性按 60 帧一帧帧走）：绝对鼠标录制手上点了 13 下，2 下落在惯性里只停住惯性（和 iPhone 一样），App 收到点击 11；右键 4、选择 1、滑动 14；相对鼠标录制不合成滑动、认作相对鼠标。

还没做的：双指滑匀成像素滚动；安卓（没有录制，安卓的按下前不带移动，此刻按虚拟鼠标键原样放行，手势不翻译）；事件成团的匀开；mouseMoved 进掩码后的开销（**未测**；掩码按登记的远控取并集，只装 UU 的用户也受影响，有常驻屏时监听一直开着）。

## 7. 工作清单

每步一个提交，在 `pr58-crossdesk` 上做：

1. 修 `endSession` 的提前 `return`（问题 1） ✅ faf4856
2. UU 手势黄金母本（只加测试） ✅ be09f95
3. 核心端口与管线（扩展形态），翻译器加「已按住」入口，先不接线 ✅ 4036cb3
4. 接线：`injector` 改回必填，加 `normalizer`；`InjectedEvents` 改成认出是哪一家；TouchTap 改走管线；契约测试改回 ✅ fba2dbe
5. CrossDesk 整理（绝对鼠标）和回放测试（两份录制做夹具） ✅ 14229e5
6. 认出相对鼠标并提示 ✅ cf01cf2、52485c3
7. 进程识别不再依赖 launchDate（问题 2） ✅ e0d0754：判在场不再看进程
8. 会话判定：电源断言为主，日志做证据和自检（实例边界改用 `Logger initialized`，从尾部扫）（问题 3） ✅ 56ccfdb、e0d0754
9. 适配器补日志（问题 4）；`remote-check crossdesk` 能报警（问题 5） ✅ b4cf96f、7a22394
10. 远控声明能力「只在启动时认显示器」；「提前准备」开关按能力显示，打开前弹确认（文案留门面）（问题 9） ✅ 276f022
11. 「提前准备」打开时的会话收尾、空闲期的指针保护（问题 7） ✅ 84d2ace
12. 屏没提前准备好时，会话中不建屏；检测 CrossDesk 有没有看到 Snug 屏并提示重启（问题 8） ✅ 85a64f9
13. 收尾整洁（问题 10）；`docs/remotes` 和设计记录同步技术事实 ✅ 995c15b 等；另按主人 11-23 提醒，界面不写死哪一家远控（a636d6b）
14. 跟进上游 issue [#200](https://github.com/kunkundi/crossdesk/issues/200)；对方修了就同步调整第 10、12 步
15. 门面一轮：README、界面文案、`crossdesk.md` 的措辞
16. 合并前：PR 从草稿改回可审阅（nexmoe 在 11-23 14:43Z 转成了草稿）

## 8. 实测清单

**现在就能做**
- A1 录一段虚拟鼠标条（验证 6.2 的假设）
- A2 把 Snug 屏设为主屏后重启 CrossDesk，看 Snug 屏的 index 会不会变成 0
- A3 ~~打开 CrossDesk 的开机自启，注销后重新登录，看 launchDate~~（判在场已不看进程，只需确认开机自启拉起的 CrossDesk 也认得出远程）
- A4 有安卓手机的话，用绝对鼠标录一段

**装开发版之后**
- B1 UU 回归：点按、单指滑带惯性、长按拖选、长按松手右键、点关闭按钮；Snug.log 的手势行和上一正式版逐字一致；`remote-check uu` 全 ✅
- B2 UU 断开后 15 秒内重连，提示是否清空（问题 1）
- B3 CrossDesk 绝对鼠标下逐项看手感：慢滑、快甩、点、长按拖、长按松手、双指点、双指滑
- B4 关闭按钮：补发事件会不会被自己再接管（回环）；隐私遮罩会不会挡住核对
- B5 隐私屏遇到换档：本机画面是否露出
- B6 「提前准备」打开时的会话收尾：窗口回到实体屏，屏的编号前后一致，不再每 2 秒 settle
- B7 断开再连，是否每次都要重新选 Snug 屏
- B8 Snug 重启而 CrossDesk 不动：还能不能推到 Snug 屏 ✅ 11-23 crossdesk-cli 实测推得到（见 3.1），判法已改成按格子推算，Snug 重启后不再提示重启 CrossDesk
- B9 控制端的分辨率菜单改 Snug 屏，Snug 会不会改回
- B10 提前准备的屏、没人远程：鼠标越过边缘滑进去，是否退回边缘 ✅ 11-23 本机：挪到 -400,400 后退回 0,400；外接屏照常
- B11 相对鼠标：手机屏顶上是否出现「手势未生效」卡，切到绝对鼠标后是否收起
- B12 先开 CrossDesk、后开「提前准备」：菜单栏和设置顶部是否提示重启 CrossDesk，重启后是否收起 ✅ 11-23 本机：开关先弹确认（取消不改、打开才建屏），设置顶部出「重启 CrossDesk 才选得到 Snug 的屏」，重启 CrossDesk 后收起
- B13 没开「提前准备」时用 CrossDesk 连：Snug 不建屏，状态提示去打开 ✅ 11-23 本机（同名断言模拟连入）：不建屏，设置顶部出提示，日志记一句
- B14 CrossDesk 1.7.7：Snug 撤掉正在推的屏时，它自动换推哪块屏 ✅ 11-23 crossdesk-cli 实测：约 2 秒后那格改推内建屏；Snug 再建的屏选不到，Snug 提示重启 CrossDesk，重启后第 0 格回到 Snug 屏（见 3.1）
- B15 提前准备的屏：远程结束后屏上的窗口 ✅ 11-23 本机（同名断言模拟连入）：用户开在屏上的窗口挪回主屏；关掉「提前准备」时同样先挪窗口再撤屏

### 8.1 用 crossdesk-cli 连回本机（11-23）

CrossDesk 的终端控制端 `crossdesk-cli`（npm `@chunkdash/crossdesk-cli`，装在草稿区）能用 9 位设备 ID 连回本机自己，`agent --stdio` 模式下按 JSON 发连接、截图、选屏、鼠标键盘动作。要先在 CrossDesk 里关掉「断开即锁屏」（`~/.cache/CrossDesk/config.ini` 的 `lock_on_disconnect`），测完改回。密码只走 `--password-fd`，不落盘。

坑：主机端画面静止时不出新帧，CLI 又要求截图和动作用的画面不超过 2 秒，所以每次新连接后几秒内截图、紧接着发一个动作；画面一变（点开、滚动）帧就又流起来。CLI 的点击是「移动、10ms 后按下、40ms 后抬起」，和 iOS 绝对鼠标的点按同形；滑动用 `sequence` 里的一串 `move`（间隔 ≤ 260ms、每步 < 80 点）；长按用原地不动、600ms 的 `drag`。

实测结果（测试版 Snug + CrossDesk 1.7.7）：
- 共享断言判在场：真连接当场认出，断开 1.5–2 秒认出断开，15 秒内重连算同一次远程
- 连上推第 0 格，就是 Snug 的屏（Snug 的屏在 CrossDesk 启动前就在时）
- B8、B14 ✅（见 3.1）
- 点按 ✅（切「全部」分段、点 App 放上屏）；单指滑 ✅（不按键的移动合成滑动，App 网格滚了 145 点）；长按松手 ✅（访达弹出右键菜单）
- 关闭按钮：发现并修了「指针窗口挡住核对」（`3e81b72`）。CrossDesk 点按前先发移动，指针先到了按钮上，窗口服务器里指针也是个窗口、总在最前，核对取到它就退回普通点击；修后先放回原位再关 ✅
- 相对鼠标提醒 ✅：连续几下从上一下停的地方开始，手机屏顶上出「手势未生效」；从远处落下一下即收起
- 没测到：隐私遮罩（CLI 连接不开隐私屏，`privacy filter requested=0`），所以 B4 的遮罩部分、B5 仍要手机测

## 9. 材料

- CrossDesk 源码：tag `v1.7.6-20261112` 与 `mcp@acf678d`，GitHub 上可直接看。
- 抓取工具：`recordings/`；录制：`Tests/Remotes/CrossDesk/Fixtures/`。
- 原始调研报告（三路研究、两版方案、核实、合成、两路审查）和实验留在本机，不进仓库；有出入时以本文为准。
