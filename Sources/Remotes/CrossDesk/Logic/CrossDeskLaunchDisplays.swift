// CrossDesk 这次启动认到了哪几块屏：它只在启动时认一次（抓屏模块初始化时），之后加的屏选不到。
// 从日志里跟着读：系统部分把新追加的行一行行交进来，遇到实例开头（Logger initialized）就从头记
import SnugCore

package struct CrossDeskLaunchDisplays: Sendable {
    /// 这次启动认到的屏；还没读到（刚启动还没认、启动那段已滚动掉、一块都没认到）为 nil
    package private(set) var displays: Set<DisplayID>?

    package init() {}

    package mutating func take(_ line: Substring) {
        guard let parsed = CrossDeskLogLine(line) else { return }
        switch parsed.event {
        case .started: displays = nil
        case .displayFound(_, let display, _): displays = (displays ?? []).union([display])
        case .sharingBegan, .sharingEnded, .lastControllerLeft: break
        }
    }

    /// CrossDesk 换了进程（重启、退了又开）：新进程启动那几句读到之前，旧的不算
    package mutating func restarted() { displays = nil }
}
