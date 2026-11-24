import Foundation
import SnugCore
import Testing

/// 每家远控一个驱动：把几种标准情形翻译成这家远控的原始信号，再经它自己的解析和映射交出观测。
/// 契约测试拿同一组断言跑每个驱动。新接一家远控：加一个驱动、放进 drivers（scripts/snug check 核对有没有漏）
protocol RemoteDriver: Sendable, CustomTestStringConvertible {
    var identity: RemoteIdentity { get }
    /// 能认出控制端的名字；认不出的远控连入时照样报在场，名字一直为空
    var namesControllers: Bool { get }
    /// 能报在推哪块屏；报不了的一直是 nil
    var reportsStreamedDisplay: Bool { get }
    /// 它注入鼠标事件的进程（可执行文件路径）
    var injectorPath: String { get }
    /// 它自己的 App
    var appBundleID: String { get }

    /// 没人远程
    func idle() -> RemoteObservation
    /// 这家远控的信号读不到（没给权限、界面认不出、日志监听没起来）
    func unreadable() -> RemoteObservation
    /// 有人远程，控制端是这几台
    func connected(controllers: [String]) -> RemoteObservation
    /// 有人远程，在推这块屏
    func streaming(_ display: DisplayID) -> RemoteObservation
    /// 这家远控启动时认到 launched、此刻在线的是 online 时的观测；不报选不到哪些屏的远控（随时认新屏）为 nil
    func reaching(launched: Set<DisplayID>, online: Set<DisplayID>) -> RemoteObservation?
    /// 手机上的这个单指操作，这家远控在 Mac 上注入成什么样的原始指针事件（它的方言）。
    /// 坐标落在基准宽度的手机屏（0, 0, 540, 950）里，时间从 10 秒起
    func touchEvents(_ gesture: FingerGesture) -> [PointerEvent]
}

/// 手机上的几种单指操作：每家整理完、经共用翻译器，App 收到的都要一样
enum FingerGesture: CaseIterable, Sendable {
    case tap, holdRelease, holdDrag, slide
}

extension RemoteDriver {
    var testDescription: String { identity.logName }
}

/// Sources/Remotes 下的每家远控都要有驱动（scripts/snug check 核对）
let drivers: [any RemoteDriver] = [UUDriver(), CrossDeskDriver()]
