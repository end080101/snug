# 远控适配层设计记录

> 2026-11-19 · 为什么这样切：调研、取舍、拍板，以及落地时相对方案的改动（第 12 节）
>
> **要接入一家远控，先看 [接入新的远控](../remotes/README.md)**（现行的端口、步骤、门禁），UU 的做法见 [UU远程 适配](../remotes/uu.md)。本文是背景：方案阶段的写法与落地后有出入的地方，以第 12 节和代码为准。
>
> 来源：三个只读调研 agent 的报告（[代码耦合与接口](research/coupling.md)、[目录与模块](research/structure.md)、[测试](research/tests.md)），加上交叉核对与取舍。调研针对抽出适配层之前的代码（ffd32ef），报告里的行号以那时为准。第 9 节的 11 项于 2026-11-19 拍板，全部按推荐执行。

## 1. 结论

- **可以切干净。** 抽出前（ffd32ef）直接引用 UU 的代码集中在：核心 9 个文件、系统层 2 个、App 层 7 个，加上测试、脚本、文档。UU 专属代码约 1280 行：纯逻辑约 630 行，系统调用约 650 行。
- **切法：**
  - 核心只留中性端口。
  - UU 做成独立适配器：纯逻辑、系统调用各一个目标，外加自己的测试目标。
  - App 只有一个登记适配器的地方。
  - 核心不认识任何适配器，由编译器保证；字符串里的残留，由 `scripts/snug check` 门禁保证（落地后按 `Sources/Remotes` 下的目录名查每一家，见 12.1）。
- **接口很小：** 身份，加上 `start`、`stop`、`sample` 三个方法。手势形态、模式恢复、主屏策略、时序常量都不进接口：要么两家情况相同，要么核心已有通用机制兜住。⚠️ 11-20 更正：手势形态并不相同（RustDesk 触摸模式实测），手势只拆了一半，见 12.4。
- **只有 UU 时行为不变，日志逐字不变**，验收时拿真机日志逐行对照。
- 11 项决定已拍板（第 9 节），全部按推荐执行。

## 2. 切分原则

1. **依赖单向。** 核心（SnugCore、SnugSystem）永远不依赖适配器；适配器依赖核心；App 只做组装。
2. **有真实第二个用例才抽象。** 以 RustDesk 1.5.3 源码事实为检验，装不进的才改接口，不为想象中的需求加成员。
3. **源码级适配器。** 不做动态插件加载，不加设置里的选择开关。只有 UU 时用户无感。
4. **防回潮。** 「核心无残留」要能用命令查（第 8 节），不靠记性。
5. **不扩大范围。** 偏胖的 Desk、DeskSet、ScreenSet 这次只改注释；系统层的测试缺口记为技术债（7.5 节）。

## 3. 抽出前的 UU 触点全景

> 本节的路径、行号都是抽出前 ffd32ef 的；现在的位置见 [UU远程 适配](../remotes/uu.md)。

### 3.1 整体搬进 UU 适配器

| 现在的位置 | 内容 |
|---|---|
| `SnugCore/Session/` | `UURemote`（身份常量）、`UUSignals`（三路证据）、`ControllerTable`（被控页界面树）、`CaptureLogParser`、`CaptureSessionState`（推流日志与状态）、`UUProcessWatch` |
| `SnugCore/Diagnostics/UUCheck.swift` | UU 兼容自检的判定 |
| `Snug/Sensing/`（整个目录） | `UUSensor`、`CaptureLogWatcher`、`ControllerReader`、`UUAccessibility`、`UURemoteApp` |
| `Snug/Debug/` | `UUDump`、`UUCheckRun` |
| 测试 | `CaptureLogTests`、`ControllerTableTests`、`UUProcessWatchTests`、`UUCheckTests`，4 份 `uuremoteserver-*.ndjson` 夹具 |

### 3.2 共用代码里夹带的 UU 语义（要中性化）

| 位置 | 问题 | 改法 |
|---|---|---|
| `ConnectionTracker`、`RemoteSession` | 直接吃 `UUSignals`；日志写死「检测到 UU 连入」 | 改吃中性的 `RemoteObservation`；日志里的名字取自适配器 |
| `UUSignals.swift:28` | 中性的 `ConnectionEvent` 放在 UU 文件里 | 先挪进 `ConnectionTracker.swift`，再整体搬走 UU 文件 |
| `Apps.swift:83-84` | 资源库排除写死 `[UURemote.bundleID]` | 排除名单改成参数，值取各适配器 bundle 的并集 |
| `SnugSystem/WindowService.swift:221` | **隐蔽：** 系统层调 `AppList.ordered` 时顺带做了排除（已核实） | 过滤统一收到 App 层的 `AppCatalog`，系统层只排序 |
| `TouchEvents.swift:60-75`、`TouchTap.swift:42,66` | 按进程名写死 `UURemoteServer` 认注入事件 | 改成中性匹配器；判断函数放核心，可测 |
| `LaunchMode.swift:42,87,89` | 核心启动参数引用 `UUCheck` 的常量（已核实） | 小时上下限归 LaunchMode 自己；参数名见决定 5 |
| `SnugLogDigest` | 解析「检测到 UU 连入（」和 `overlay=`、`capture=`；跨模块的字符串约定 | 见 3.5 |
| `Package.swift:32` | `SnugCoreTests` 声明了 Fixtures 资源，而里面只有 UU 的夹具 | 资源声明随夹具挪到 UU 测试目标 |
| `AppController`、`main.swift` | 直接创建 UU 感知器、直接调用 UU 诊断 | 改由唯一登记处 `Snug/App/Remotes.swift` 提供 |

### 3.3 隐性耦合：留在共用代码里（核心、系统层、App 层），改成中性命名并注明「UU 实测」

| 位置 | 为什么不进接口 |
|---|---|
| `ScreenFit` 遮挡（竖屏上下各 91 点、横屏 82+72）、`TouchStyle` 平板右上让位 | 建屏早于知道是哪家远控来连（常驻主屏甚至不等远程），按会话归属提供不了 |
| `ScreenPlan` 常驻主屏 | 新连接从主屏开始，UU 实测和 RustDesk 源码一致 |
| `DeskSet`、`ScreenSet` 停推流后的模式补救 | 走的是通用的显示器变化复查，代码里没有 UU 分支 |
| `ConnectionTracker` 防抖 1.5 秒、静默期 5 秒 | 对按进程判在场的远控最多晚判几秒，无害；等实测出不同值再说 |
| `TouchEvents` 只接管左键、`TouchTranslator` | RustDesk 的单指操作同样是左键；滚轮、长按右键不在接管范围 |
| 重连等待期收指针、`Desk.Notice.reshaped` | 前者对任何远控都成立；后者只有 UU 的实测依据，RustDesk 实测后再定 |

### 3.4 不是适配层，别误搬

- 旧版「UU远程伴侣」的冲突检测：`LegacyApp`、`LegacyNotice` 等。它处理的是和 Snug 前身的冲突，不是远控。
- `AboutView` 里对 UUyc-companion 的致谢，以及「非 UU远程 官方软件」的免责声明。

### 3.5 最容易「悄悄失效」的一处：日志约定

日志格式由核心产出，由 UU 自检解析：

- 产出方：`ConnectionTracker`、`AppController.describe`、`ScreenSet`、`Desk`。
- 解析方：`SnugLogDigest`，结果交给 `UUCheck`。

如果措辞改了，`UUCheck.detection` 认不出连入信号，会直接返回 nil（`UUCheck.swift:222`，已核实），报告里的「连接检测」这一项悄悄消失、不报错。

处理：
- 解析器留在核心，和产出方同一个模块。
- 产出方的拼接抽成函数，加往返测试：用产出函数生成一行日志，再交给解析器，断言能认回来。
- 「读不到名字」现在两边各写了一份，合成一处。
- UUCheck 在「有远程记录、却一条连入信号都没认出」时改报「需留意」，不再返回 nil。

## 4. 目标结构

### 4.1 目录

```
Sources/
  SnugCore/
    Remote/                    ← 原 Session/ 改名（决定 3）
      RemoteAdapter.swift      ← 新：端口协议、RemoteIdentity、RemoteObservation、InjectedEventSource
      ConnectionTracker.swift  ← 含 ConnectionEvent，改吃中性观测
      SessionEpisode.swift
      RemoteSession.swift      ← 加归属规则、会话日志描述
      SnugLogDigest.swift      ← 从 Diagnostics/ 并入；Diagnostics/ 删除，不留单文件目录
  SnugSystem/                  ← TouchEvents 里的 UUEventSource 改成中性的注入事件过滤
  Remotes/
    UU/
      Logic/   → 目标 RemoteUU：UURemote、UUSignals、ControllerTable、CaptureLogParser、CaptureSessionState、UUProcessWatch、UUCheck
      System/  → 目标 RemoteUUSystem：UURemoteAdapter（原 UUSensor）、UURemoteApp、UUAccessibility、ControllerReader、CaptureLogWatcher、UUDump、UUCheckRun
  Snug/
    App/Remotes.swift          ← 新：唯一登记适配器的地方，加诊断分派
    （Sensing/ 删除；Debug/ 只剩 Renderer、RenderSamples、ScreenProbe）
Tests/
  SnugCoreTests/               ← 不再带资源；Support/RemoteFakes.swift 放假身份、假观测
  Remotes/UU/                  → 目标 RemoteUUTests：Fixtures/（4 份 ndjson）、Support/UUFixtures.swift
  RemoteContractTests/         ← 决定 4
```

以后接 RustDesk：加目录和三个目标、在 `Remotes.swift` 登记、写契约驱动；它的注入事件要按 `eventSourceUserData` 认，得给核心的 `InjectedEventSource` 和系统层的 `InjectedEvents` 加一处（见第 5 节）。完整步骤以 [接入新的远控](../remotes/README.md#步骤) 为准。

### 4.2 依赖（箭头指向被依赖方）

```
SnugSystem      → SnugCore
RemoteUU        → SnugCore
RemoteUUSystem  → RemoteUU, SnugSystem, SnugCore
Snug（App）      → SnugCore, SnugSystem, RemoteUUSystem
SnugRelease     → SnugCore
SnugCoreTests   → SnugCore
RemoteUUTests   → RemoteUU, SnugCore（带 Fixtures）
RemoteContractTests → SnugCore, 每家的纯逻辑目标（RemoteUU）
```

无环。SnugCore、SnugSystem 不依赖任何 `Remote*` 目标，核心里一旦引用 UU 符号就编译不过。

### 4.3 两个细节

- **目标不能叫 `UURemote`：** 目标里有同名的 `enum UURemote`，模块名和类型同名时，`UURemote.xxx` 会出现查找歧义。所以目标统一叫 `Remote<家>`。
- **访问级别用 `package`：** 当前 tools-version 是 6.0，支持 `package`。适配器内部类型跨目标可见，但不必标成 `public`；App 实际只需要看到 `UURemoteAdapter` 和诊断入口。

### 4.4 考虑过、没采用的方案

- **在现有三个目标里各开 `UU/` 子目录：** UU 散在三处，没有完整的落脚点；「核心不依赖 UU」只能靠自觉；测试也分不了包。否决。
- **每家只建一个目标，内部分 `Logic/`、`System/` 两个文件夹：** 目标少一个，但纯逻辑那半边没有编译器约束，只能靠 grep 防它 `import AppKit`，测试也要连带链接系统层。作为次选，见决定 1。
- **单独建一个端口目标 `SnugRemote`：** 它仍要依赖 SnugCore，换不来真正的隔离，端口一共才几个文件。否决。

## 5. 适配接口

```swift
public struct RemoteIdentity: Sendable {
    public let logName: String                // "UU"：日志、命令行参数（决定 6）
    public let displayName: String            // "UU远程"：界面文案
    public let bundleIDs: Set<String>         // App 资源库排除
    public let injector: InjectedEventSource  // 手势只接管它注入的事件
}

public struct InjectedEventSource: Equatable, Sendable {
    public let executableName: String         // UU：UURemoteServer
    public func matches(executableName: String) -> Bool   // 纯函数，放核心测
}

public struct RemoteObservation: Equatable, Sendable {
    public var present: Bool                  // 有在场的正面证据
    public var controllers: [String]          // 空 = 没认出，不代表没人
    public var streamedDisplay: DisplayID?    // nil = 不知道（AppState.watching 已把 nil 当作「在看」）
    public var evidence: String               // 写进连入、断开日志的信号快照
}

@MainActor public protocol RemoteAdapter: AnyObject {
    var identity: RemoteIdentity { get }
    func start()
    func stop()
    func sample(wallClock: Date) -> RemoteObservation   // 推流日志的时间戳是墙钟，会话层用单调钟
}
```

拿 RustDesk 逐项检验：

| 成员 | UU 怎么实现 | RustDesk（源码事实）装得下吗 |
|---|---|---|
| `bundleIDs` | `com.netease.uuremote` | `com.carriez.rustdesk`，装得下 |
| `injector` | 进程名 `UURemoteServer` | 能装下，但不够精确：它的 `--server` 和界面是同一个可执行文件。它的事件带 `eventSourceUserData=100`，接它时再加一个可选的 `userData` 字段，纯增量。注意 Snug 补发事件会把这个字段改写成自己的标记（`TouchEvents.swift:33`），所以匹配必须看原始事件；现有逻辑就是先看原始事件 |
| `start`/`stop` | KVO 加 `log stream` 子进程 | 盯 `--cm` 进程或窗口，装得下 |
| `sample` | `present` 取 `UUSignals.isPresent`；`evidence` 取 `UUSignals.description`，日志逐字不变 | `present` 看 `--cm` 在不在；控制端取登录信息；推流屏先报 nil，装得下 |

**不进接口**（YAGNI，附理由）：
- 手势形态：两家的单指操作一致。⚠️ 11-20 更正：不成立。这条依据源码阅读、没有实测，RustDesk 触摸模式实测发的是不按键的移动，见 12.4。
- 遮挡：建屏时还不知道是哪家来连。
- 只推主屏：两家都从主屏开始。
- 模式恢复：通用的复查已经兜住。
- 按家调时序：没有实测依据。
- 多路推流屏：RustDesk 认不出时报 nil 即可。
- 诊断方法：由 `Remotes.swift` 的分派表直接调用，不进协议。
- 控制端设备类型：用不上。

## 6. 多个适配器并行：一次远程只归一家

规则写在 `RemoteSession`，纯逻辑，可测：

1. **未连接时**（空闲，或断开后的重连等待期）：归属给登记顺序里第一个报告在场的适配器。都不在场就保留原归属，把它这一拍的真实观测交给 `ConnectionTracker`，让断开日志带的仍是它的信号快照。
2. **已连接时：** 归属不变，只把归属方的观测交给 `ConnectionTracker`。别家报告在场时，只在首次出现记一条日志「另有 X 报告连接，本次远程归 Y」。
3. **重连等待期内换了一家：** 算同一次远程（resumed），屏不撤不建，控制端、推流屏、`remoteName` 改取新的归属方。会话结束（ended）时清空归属。
4. **手势：** 接管所有已登记适配器注入的事件，取并集（决定 9）。

**只有 UU 时：** 每拍交给 `ConnectionTracker` 的就是 UU 的观测，规则退化成现在的逻辑。要加一条测试把这一点钉住。

**已知风险：** UU 漏掉停流日志时会一直报告在场、一直占着归属，另一家连入只能拿到屏和手势，拿不到控制端和推流屏。兜底和今天一样：在设置里关屏复原。

## 7. 测试

### 7.1 现状

只有一个测试目标 `SnugCoreTests`：41 个文件、约 445 个用例、4 份夹具，SnugSystem 没有测试。按和 UU 的关系分：

| 类别 | 用例数（约） | 去向 |
|---|---|---|
| 只测 UU | 43 | 连同夹具整体搬进 `RemoteUUTests`，断言不改 |
| 测核心，但用 UU 类型或 UU 数值当输入 | 20 | 留在核心，改用中性假观测；其中测「UU 原始信号怎么算在场」的部分拆到 UU |
| 诊断、启动参数相关 | 若干 | 随 UUCheck、LaunchMode 的去向走 |
| 和 UU 无关 | 其余 | 不动，只把测试名、注释里归给 UU 的措辞改成中性 |

需要拆开的典型：`ConnectionTrackerTests` 里测 `UUSignals.description` 和 `isPresent` 的 2 个用例搬到 UU，其余改用中性观测。`SessionTests` 的「回归 #1」保留两份：核心一份写成中性的「在场、无名字，300 秒也不断」，UU 一份端到端，从 UU 原始信号经映射一路走到会话。

### 7.2 目标布局

- **`SnugCoreTests`：** 只依赖 SnugCore，不带资源。核心测试里不再出现任何 UU 类型（门禁查）。
- **`RemoteUUTests`：**
  - 子目录：`Capture/`、`Controllers/`、`Process/`、`Signals/`、`Diagnostics/`、`Fixtures/`、`Support/`。
  - 两份重复的夹具读取函数合成一份 `UUFixtures.swift`。
  - ~~`SnugLogDigestTests` 里有个私有 `at(String)`，和核心的 `at(Double)` 跨目标同名，改名为 `stamp`。~~ 按第 11 节，`SnugLogDigest` 留在核心，测试也留在 `SnugCoreTests`，不用改名。
- **以后每家一个同构的测试目标。**

### 7.3 新增测试（先写测试、亲眼看它失败）

- **核心：**
  - 多适配器归属：A 先到归 A；A 在场时 B 被忽略；A 断开后 B 连入判 resumed；结束后清空归属；同一拍都在场时按登记顺序。
  - 「只有一家时，ConnectionTracker 每拍的输入与现在相同」。
  - 注入事件匹配的正例、反例、边界。
  - 日志往返（3.5 节）。
- **UU：**
  - UU 原始观测到中性观测的映射：推流未知不算缺席；表格未识别不算缺席；只有覆盖窗口也算在场；推流屏只在推流时有值。
  - 身份声明。

### 7.4 适配器契约测试（决定 4）

一个 `RemoteContractTests` 目标，每家写一个驱动，提供空闲、连入、换控制端、读不到、注入事件、本机事件这几种原始输入。参数化跑同一组断言（落地后的驱动接口与断言见 12.1）：

- 空闲和读不到都不算在场。
- 标准时序产出完全相同的会话转换序列：began → controllersChanged → interrupted → resumed → interrupted → ended。
- 能报推流屏的断言屏号；不能报的断言一直是 nil，不允许跳过不测。
- 注入事件为真，本机事件和 Snug 补发事件为假。
- 自身 bundle 不出现在资源库里。

**完整性检查：** `Remotes.swift` 里登记的适配器和契约驱动必须一一对应，在 `scripts/snug check` 里比对。这样新接一家漏写驱动，check 当场就失败。

### 7.5 本次不做（记为技术债）

系统层几处判断没有测试：
- `CaptureLogWatcher` 的退避重启。
- `ControllerReader` 的结果新鲜度与代次。
- `UUAccessibility` 的环检测和节点上限。
- `TouchTap` 的分派。

要测得先抽成纯值类型，属于另一件事，不在这次范围里。

## 8. 防回潮：`scripts/snug check` 加门禁

> 落地后的门禁比本节更严，以 12.1 和 [防回潮](../remotes/README.md#防回潮) 为准。

1. `Sources/SnugCore`、`Sources/SnugSystem` 的字符串字面量里不许出现 UU 身份（如 `com.netease.uuremote`、`UURemoteServer`、「检测到 UU」）。注释里「UU 实测」这类出处说明允许。
2. `import RemoteUU*` 只允许出现在 `Snug/main.swift` 和 `Snug/App/Remotes.swift`。
3. `Tests/SnugCoreTests` 里不许出现 UU 类型名。
4. `Package.swift` 声明的测试目标和 `Tests/` 下的目录一致（SwiftPM 会静默忽略没声明的目录）。
5. `Remotes.swift` 登记的适配器和契约驱动一一对应（若采用契约测试）。

类型引用由编译器管（4.2 节），字符串残留由这些门禁管。

## 9. 已拍板（2026-11-19，全部按推荐）

| # | 问题 | 决定 | 未采用 |
|---|---|---|---|
| 1 | 每家几个目标 | **两个**（Logic、System），纯逻辑与系统调用的分层由编译器把关，和现有 SnugCore/SnugSystem 的分法一致 | 一个目标、内部两个文件夹，再加 grep 门禁 |
| 2 | 适配器放哪 | **归到 `Sources/Remotes/<家>/`、`Tests/Remotes/<家>/`**（Package.swift 写明 path），「接新远控去哪看」一眼可见 | 默认路径平铺：`Sources/RemoteUU`、`Sources/RemoteUUSystem` |
| 3 | `SnugCore/Session` 改名 `Remote` | **改**，端口、会话、日志解析都在里面，便于社区找入口 | 不改，少一批改动 |
| 4 | 契约测试现在建不建 | **建**，只有 UU 一个驱动。它和接入文档一起构成留给社区的「口子」 | 等第二家来了再抽 |
| 5 | 诊断参数 | **中性化：** `--dump-remote <名>`、`--check-remote <名> [小时]`、`scripts/snug remote-check <名>`；旧的 `-uu` 不留别名，文档和记忆同步改 | 保留 `--dump-uu`、`--check-uu`、`uu-check`，门禁单独放行 |
| 6 | 日志是否逐字不变 | **不变：** 身份里带 `logName`（"UU"），日志仍写「检测到 UU 连入」，验收时逐行对照 | 日志改用显示名「UU远程」，解析器两种都认 |
| 7 | 遮挡常量 | **留核心：** `uuInset` 改成 `clientToolbarInset`，注明按 UU 实测标定 | 每块屏加「给哪家用」字段（相当于选择开关，违反原则 3） |
| 8 | 界面文案 | **运行期提到工具名的地方**用 `displayName` 拼（只有 UU 时逐字不变）；**陈述 UU 特有事实的静态文案**（设置页「一次只让一台设备控制」等）作为产品定位保留，接第二家时再改 | 全部改成中性说法 |
| 9 | 手势接管范围 | **所有已登记适配器注入的事件**，实现简单，归属卡住时也稳 | 只接管当前归属方，手势监听要知道会话归属 |
| 10 | 两家同时在场 | **已连接时不抢；未连接时按登记顺序** | 先到先得（按出现时刻） |
| 11 | 系统层测试缺口 | **本次不做**，记技术债 | 这次一并抽纯值类型补测试 |

## 10. 落地顺序与验收

在本分支上每步一个 commit，每步跑 `scripts/snug check`，记录测试用例数（基线约 445，只增不减）：

1. **核心中性化（先写测试）：** 加入 `RemoteObservation` 等类型；挪 `ConnectionEvent`；`ConnectionTracker`、`RemoteSession` 改吃中性观测，暂由 App 层做 UU 映射；核心测试改用中性假观测；日志产出函数和往返测试；UUCheck 的「静默消失」改报需留意。
2. **注入事件与资源库排除：** 中性匹配器，`TouchTap` 改为注入；排除名单改成参数，过滤收到 `AppCatalog` 一处，系统层不再过滤。
3. **建适配器目标并物理搬迁：** 用 `git mv` 保留历史；`Remotes.swift` 登记；`LaunchMode` 去掉对 UU 的依赖；搬测试和夹具，挪资源声明。
4. **多适配器归属：** 加归属规则和测试，`AppState` 加 `remoteName`，运行期文案改用它。
5. **契约测试与门禁**（视拍板结果）。
6. **收尾：**
   - 注释改中性：约 40 处「UU」改成「远控」，保留「UU 实测」出处。
   - 文档：`docs/how-it-works.md` 拆出中性的连接判定；新建 UU 适配文档和「接入新的远控」指南；`docs/development.md` 更新代码结构、依赖图和命令。
   - 记忆同步。

**验收：**
- `scripts/snug check` 全绿，用例数不降，门禁全过。
- 真机连一次 UU：Snug.log 里连入、断开、会话、建屏这几行和改动前逐字一致。
- `remote-check uu` 全部 ✅。

## 11. 三份报告的分歧与裁决

| 分歧 | 各方意见 | 采纳 | 理由 |
|---|---|---|---|
| 每家几个目标 | 耦合：一个；结构：两个；测试：未定 | 两个（决定 1） | 纯逻辑与系统分层由编译器把关，跟现有分层一致；代价只是 Package.swift 多一条 |
| `SnugLogDigest` 放哪 | 耦合、结构：留核心；测试：随 UUCheck 搬到 UU（唯一使用者） | 留核心 | 它解析的是核心产出的日志。放在产出方旁边，改措辞时往返测试当场变红；搬到 UU 就成了跨模块的暗约定，正是 3.5 节的失效路径 |
| 多适配器汇总放哪 | 耦合：新建 `Remotes.swift`；结构：`AppController` 里直接循环；测试：把编排抽进核心 | `Remotes.swift` 加核心里的归属规则 | 唯一登记处便于社区接入，也便于门禁 2；把 AppController 的整段编排抽进核心超出本次范围 |
| 注入事件匹配的字段 | 耦合：只要进程名；结构：进程名加 userData；测试：值描述 | 只要进程名，判断函数放核心 | userData 等接 RustDesk 时再加；判断放核心是为了能测（SnugSystem 没有测试目标） |
| 契约测试 | 耦合：等第二家；测试：现在建 | 现在建，只有 UU 一个驱动（决定 4） | 主人要「留口子给别人做」，契约测试就是给接入者的验收清单 |
| 日志措辞 | 耦合：改用显示名；结构：用 logName 保持逐字不变 | 逐字不变（决定 6） | 大改动最可靠的验收方式就是日志逐行对照 |
| 诊断参数 | 耦合：中性化不带名字；结构：带适配器名字；测试：二选一 | 中性化、带名字（决定 5） | 带名字之后接第二家不用再改参数 |

## 12. 落地结果

2026-11-19 落地并合入 main。下列是相对上面方案的改动，多数来自落地后的一轮审查（5 个维度并行审，1 个核实者逐条核对：25 条发现，去重后 16 个问题，全部修复）。

### 12.1 与方案不同的地方

| 项 | 方案 | 落地 | 为什么 |
| :--- | :--- | :--- | :--- |
| 身份从哪来 | 适配器实例上的 `identity` | `RemoteAdapter` 要求静态的 `identity` 和 `init()`，实例的 `identity` 由扩展取 `Self.identity`；身份定义在纯逻辑目标里（`UURemote.identity`），适配器和契约驱动都引用它；登记处 `Entry` 存适配器类型和两个诊断入口，不另存身份 | 审查发现登记处和实例各有一份身份，可能对不上；现在只有一份，`Remotes.swift` 也不必再 import 纯逻辑目标 |
| 资源库排除 | 排除名单改成参数，过滤收到 `AppCatalog` | 排除放进 `AppList.sorted(_:excluding:)` 和新增的 `AppList.refreshed`，`AppCatalog` 每轮刷新都经它们出列表；在跑的 App 读完窗口后再滤，和原来一致 | 只在 `AppCatalog` 里滤的话，漏调过滤测试照样全过（App 层没有测试） |
| 日志摘要 | 解析器留核心，加往返测试 | 另加按远控归属：会话行归到前面最近一行「检测到 <远控> 连入」的那家，找不到的照旧算进来 | 会话行不带远控名，接第二家后 UU 自检会把别家的远程算成 UU 的 |
| 观测怎么交给会话 | `sample` 交 `RemoteObservation` | 另有 `RemoteReading`（哪家加观测）；`RemoteSession.tracked` 是这一拍跟的那份 | 归属规则要知道观测来自哪家 |
| 注入事件匹配 | `matches(executableName:)` | `matches(executablePath:)`，按路径的最后一段比 | 系统层读到的是来源进程的完整路径 |
| 门禁 | 5 条 grep | 名字检查从「字符串字面量里的 UU」扩大到核心、系统层、核心测试的所有代码行，名字取 `Sources/Remotes` 下的每个目录，按子串、大小写都拦，只放过单独一行的注释，撞上无关子串走放行表（`UUID`、`com.todesktop`）；import 只放行 `Snug/App/Remotes.swift`（`main.swift` 经 `Remotes.dump`、`check` 分派），只认行首的 import 语句，`@testable`、`internal import` 等写法都认；`Package.swift` 交给 `swift package dump-package` 解析，检查的目录也从它取，按目录核对每家的三个目标、登记（`<家>RemoteAdapter.self`）、契约依赖与驱动，注释掉的不算；纯逻辑目标只能 import Foundation、SnugCore，只依赖 SnugCore；grep 出错报错退出，不当成没命中 | 审查发现小写字面量、多行写法、只 import 不登记都能绕过；合并前两轮核查又发现：名字检查只认 UU、`UUIdentity` 能混过、ToDesk 会撞上 Cursor 的 bundle、纯逻辑 import 行尾带注释被误拦、注释掉的登记照样通过、grep 出错被当成干净 |
| 契约测试 | 驱动提供六种原始输入；标准时序产出相同的转换序列 | `RemoteDriver`（`Tests/RemoteContractTests/RemoteDriver.swift`）交 `idle()`、`unreadable()`、`connected(controllers:)`、`streaming(_:)` 四种情形，以及身份、能否报控制端与推流屏、注入进程路径、自家 bundle；注入事件拿注入进程路径和几条固定路径比；认不出控制端的远控跳过 `controllersChanged`；另断言每次观测的信号快照不为空，日志名不为空、不含空格、不重名 | 注入事件、本机事件在系统层生成，契约测试只能比路径；各家能报的信号不同，序列按能力分支 |
| UUCheck 的连接检测 | 认不出连入时报需留意 | 同上，另外信号快照读不出也报需留意；推流信号全部未知时这一项照旧不出 | 只修静默失效，其余输出和抽出前一致 |

### 12.2 验收

- `scripts/snug check`：门禁全过，测试 445 → 472 例全绿（`SnugCoreTests` 415、`RemoteUUTests` 50、`RemoteContractTests` 7）
- 门禁：11 个违规样本各自拦下，目标写成多行照常通过；名字检查改为按目录后，另 10 个样本结果符合预期（含同一行 UUID 加 UU、行尾注释、第二家 Demo 的 bundle 与进程名）；第二轮核查后重写，24 个样本全部符合预期（含 `UUIdentity`、注释掉的登记、纯逻辑行尾注释、ToDesk 目录、目录名带点），grep 出错时报错退出；契约测试改坏 UU 驱动后当场变红
- 照指南接入：只看 [接入新的远控](../remotes/README.md) 的 agent 在隔离工作区先后接入假远控 Demo、Parsec（第二次用修订后的指南），`scripts/snug check` 都一次通过，指南里写漏的地方已补
- 与抽出前对比：81 张界面渲染逐字节一致；`--dump-remote uu`、`--check-remote uu` 与旧 `--dump-uu`、`--check-uu` 输出逐字一致
- 真机（UU远程 4.48.1，iPhone）：连入、会话、建屏、手势开启、放窗口、断开、重连等待、结束、撤屏 14 条日志里 13 条与之前正式版的写法逐字一致，剩下 1 条是没改动、之前没触发过的指针收回（#29）；资源库里没有 UU远程；点按、滚动、长按右键正常；`remote-check uu` 7 项全部 ✅

### 12.3 本次不做（技术债）

见 7.5：系统层几处判断没有测试（`CaptureLogWatcher` 的退避重启、`ControllerReader` 的结果新鲜度、`UUAccessibility` 的环检测与节点上限、`TouchTap` 的分派），要先抽成纯值类型才能测。

另有手势整理下放到各家适配器，见 12.4。

### 12.4 已知疏漏：手势只拆了一半

2026-11-20 发现，待 RustDesk 的 PR 来了一起拆。**11-23 已拆**（接 CrossDesk 时，PR #58）：端口是 `TouchNormalizer`（`Sources/SnugCore/Touch/TouchNormalizer.swift`），身份里声明 `normalizer`，分派在纯值的 `TouchPipeline`（还掉了 7.5「`TouchTap` 的分派没有测试」），翻译器加了「远控已认出长按、滑动」的入口；只登记 UU 时逐字不变由 `TouchGoldenMasterTests` 守着。下面是当时的记录，拆法和草案一致；补发事件仍是拷贝后改写记号（CrossDesk 的记号打在事件本身，和 UU 同一条路径，真机待验）。

**现状**：手势链路全部共用。适配器只在身份里声明 `injector`（哪个进程注入的事件归它）。系统层的 `TouchTap` 全局只有一个，启动时收齐各家的 `injector`（`AppController.swift` 里 `TouchTap(injectors:)`），截下远控注入的事件。核心的 `TouchTranslator` 也只有一个，只认「按下 → 拖动 → 抬起」这一种原料，按 iPhone 的习惯翻译成点击、滚动、长按选择、右键。

**疏漏**：第 1、5 节认定「两家的单指操作一致」，手势形态不进接口。这条依据的是 RustDesk 1.5.3 的源码阅读，没有实测，不成立。社区 fork 的实测（Morzorz/snug 的 `rustdesk-adapter` 分支，`4447bb5`）：RustDesk 触摸模式把手指滑动发成不按键的移动，点按只发一个孤立的抬起，长按由它自己发右键。共用的翻译器没有原料可用，接入方只能改共用的 `TouchTap`，改动会一并作用于 UU。根因：拆适配层时只把「认出是谁注入的」交给了各家，没把「把自家事件整理成标准输入」也交出去。

**决定**（主人 11-20）：现在不拆。等 RustDesk 的 PR 来了一起审，在它的实现基础上拆，把各家的手势整理分配到各自的适配器里。

**拆法**（草案，审 PR 时定稿）：
- 端口加一项「手势整理」：每家把自家注入的原始事件整理成标准触控输入（按下、拖动、抬起，带位置和时间），共用的 `TouchTranslator` 不动
- UU 的整理是直通，即现有行为；RustDesk 的整理放进它自己的目标：无键移动合成轨迹、停手超时收尾、长按让位给它自己发的右键
- 整理逻辑写成纯值类型，放各家的纯逻辑目标，可单测；要超时收尾的，由系统层按时钟喂「超时拍」。顺带还掉 7.5 里「`TouchTap` 的分派没有测试」这条债
- `TouchTap` 只剩：截获事件 → 按 `injector` 认出是哪家 → 交它整理 → 交翻译器 → 执行指令。补发事件用自己的事件源重建（`eventSourceUserData` 是事件源的属性，改写拷贝不生效，fork 中实测）仍留在系统层
- 契约测试加一组：各家把自家典型的点按、滑动、长按序列整理成同一串标准输入
- 验收照 12.2：只登记 UU 时，手势行为与日志逐字不变

**审那个 PR 时另要逐条核实的**：fork 里还一并做了几处不属于手势整理的改动，作用范围要逐条确认：远程期间隐藏 Snug 屏上的系统光标（按代码看对所有远控生效）；点按吸附到控件中心（每次点按查一次辅助功能）；点按反馈圈（黄圈、蓝框、红点，像调试画面）；快滑成批到达不再判成长按（改的是共用翻译器）。每条先问：是不是通用、会不会改变只有 UU 时的行为。`.memory` 的改动不收。

### 12.5 接 CrossDesk 时的端口增补（11-23，PR #58）

都按「有第二家的真实用例才加」：

- `RemoteIdentity.seesScreensOnlyAtLaunch`：只在自己启动时认显示器（CrossDesk）。据此显示「提前准备虚拟屏」；没提前准备时远程中不建屏（`ScreenPlan` 的 `seesNewScreens`）。
- `RemoteIdentity.opensOnMainScreen`：连上时先推 Mac 的主屏（UU）。「设为主屏每次连接即进入」只按声明了的那几家说。
- `RemoteObservation.knownDisplays`：只在启动时认屏的远控报它这次启动认到的屏，`RemoteReading.unseen` 算出看不到的 Snug 屏，提示重启它；别家为 nil（契约测试守着）。
- `ScreenWish.prepared`：提前准备的屏，`resident` = 设为主屏 || 提前准备；远程结束时只收拾提前准备的屏。
- 自检：条目与报告在 `SnugCore` 的 `RemoteCheck`，取证工具（读 Snug 日志、扫包、写材料）在 `SnugSystem` 的 `RemoteCheckTools`，各家只写判定（`UUCheck`、`CrossDeskCheck`）。
- 界面不写死哪一家：提到远控时用登记处的名单或这次远程的那家（`AppState.remoteNames`）。

## 附：调研原始报告

- [research/coupling.md](research/coupling.md)：代码耦合与接口，72 条
- [research/structure.md](research/structure.md)：目录、模块与依赖，34 条
- [research/tests.md](research/tests.md)：测试，33 条

每条都带 `文件:行号`（抽出前的 ffd32ef）。原始报告里的建议在上面各节已经取舍过；有冲突时以本文为准。
