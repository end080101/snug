// CrossDesk 这次启动认到了哪几块屏、此刻选得到哪几块：它只在启动时认一次（抓屏模块初始化时），认到几块就有几格，
// 之后加的屏没有格子。开始推某一格时先按这格记的编号找，找不到就换成系统此刻屏幕列表里同一序号的那块（CrossDesk 1.7.7；
// 11-23 实测 Snug 重启换了编号，日志 display mapping refreshed: slot=0, old_id=24, new_id=25，照样推到新屏）。
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

    /// 此刻选得到的屏（online：系统此刻在线的全部屏）；还没读到为 nil。认到的还在线的都选得到；
    /// 没认过的新屏，不多于空出来的格就按序号落上去，也选得到。多了就一律算选不到：
    /// 哪块落在哪格看系统的排序，Snug 不知道，宁可多报（实测 Snug 的屏总排第 0，换编号的那块落回原来那格）
    package func reachable(online: Set<DisplayID>) -> Set<DisplayID>? {
        displays.map { Self.reachable(found: $0, online: online) }
    }

    /// 同上，认到的屏（found）由调用方给（自检从整段日志里取）
    package static func reachable(found: Set<DisplayID>, online: Set<DisplayID>) -> Set<DisplayID> {
        let kept = found.intersection(online)
        return online.count - kept.count <= found.count - kept.count ? online : kept
    }

    /// CrossDesk 换了进程（重启、退了又开）：新进程启动那几句读到之前，旧的不算
    package mutating func restarted() { displays = nil }
}
