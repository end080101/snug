// 远控适配层的端口：核心只认这几样，不认识具体是哪家远控。每家远控一个适配器（Sources/Remotes），在 App 层登记（Snug/App/Remotes.swift）。
// 适配器每拍交一份中性的观测；连接判定、会话、建屏、手势翻译都在核心，各家共用
import Foundation

/// 一家远控的身份
public struct RemoteIdentity: Equatable, Sendable {
    /// 写进日志和命令行参数的名字（「检测到 UU 连入」）。日志措辞靠它保持不变，自检也按它认
    public let logName: String
    /// 界面上的名字（「在 UU远程 中选择 Snug 的屏」）
    public let displayName: String
    /// 这家远控自己的 App：不出现在 App 资源库里（把遥控器放到 Snug 的屏上没有意义，退了它远程就断了）
    public let bundleIDs: Set<String>
    /// 被远程时注入鼠标事件的进程：手势翻译只接管它发来的
    public let injector: InjectedEventSource
    /// 这家注入的指针事件怎么整理成标准手指输入（手势层，见 TouchNormalizer）；远控发的就是手指的按下、拖动、抬起时直通
    public let normalizer: any TouchNormalizer.Type

    public init(logName: String, displayName: String, bundleIDs: Set<String>, injector: InjectedEventSource,
                normalizer: any TouchNormalizer.Type = DirectTouch.self) {
        self.logName = logName
        self.displayName = displayName
        self.bundleIDs = bundleIDs
        self.injector = injector
        self.normalizer = normalizer
    }

    /// 元类型不能自动比较：整理按类型本身比
    public static func == (a: Self, b: Self) -> Bool {
        a.logName == b.logName && a.displayName == b.displayName && a.bundleIDs == b.bundleIDs && a.injector == b.injector
            && ObjectIdentifier(a.normalizer) == ObjectIdentifier(b.normalizer)
    }
}

/// 认哪个进程注入的事件：按来源进程的可执行文件名认，本机的触控板、鼠标不是它发的
public struct InjectedEventSource: Equatable, Sendable {
    public let executableName: String

    public init(executableName: String) {
        self.executableName = executableName
    }

    /// executablePath：事件来源进程的可执行文件路径，读不到时为空串
    public func matches(executablePath: String) -> Bool {
        (executablePath as NSString).lastPathComponent == executableName
    }
}

/// 一拍里对一家远控的观测
public struct RemoteObservation: Equatable, Sendable {
    /// 有人在远程的正面证据。读不到、没认出都不算缺席：适配器只在确有证据时报在场
    public var present: Bool
    /// 认出的控制端，按适配器给的顺序。空 = 没认出，不代表没人
    public var controllers: [String]
    /// 此刻在推的屏。nil = 不知道，不代表没在推（AppState.watching 把 nil 当作「在看」）
    public var streamedDisplay: DisplayID?
    /// 写进连入、断开日志的信号快照：排查误判时才知道是哪一路信号在变
    public var evidence: String

    public init(present: Bool, controllers: [String], streamedDisplay: DisplayID?, evidence: String) {
        self.present = present
        self.controllers = controllers
        self.streamedDisplay = streamedDisplay
        self.evidence = evidence
    }
}

/// 一家远控这一拍的观测，带上是哪家
public struct RemoteReading: Equatable, Sendable {
    public let remote: RemoteIdentity
    public let observation: RemoteObservation

    public init(remote: RemoteIdentity, observation: RemoteObservation) {
        self.remote = remote
        self.observation = observation
    }
}

/// 一家远控的适配器：盯着这家远控在本机留下的痕迹（进程、日志、界面），每拍交一份观测
@MainActor
public protocol RemoteAdapter: AnyObject {
    /// 身份是这家远控的，不是某个实例的：登记处、诊断命令、运行中的适配器都从这里取，只有一份
    static var identity: RemoteIdentity { get }
    init()
    /// App 开始监控时调一次
    func start()
    /// 退出收尾前调一次
    func stop()
    /// 每拍调一次。wallClock 是墙钟（系统日志的时间戳是墙钟）；会话层另用单调时钟
    func sample(wallClock: Date) -> RemoteObservation
}

extension RemoteAdapter {
    public var identity: RemoteIdentity { Self.identity }
}
