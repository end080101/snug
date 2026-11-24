// CrossDesk 这次启动认到了哪几块屏、此刻选得到哪几块：它只在启动时认一次（抓屏模块初始化时），认到几块就有几格，
// 之后加的屏没有格子。开始推某一格时先按这格记的编号找，找不到就换成系统此刻屏幕列表里同一序号的那块（CrossDesk 1.7.7；
// 11-23 实测 Snug 重启换了编号，日志 display mapping refreshed: slot=0, old_id=24, new_id=25，照样推到新屏）。
// 从日志里跟着读：系统部分把新追加的行一行行交进来，遇到实例开头（Logger initialized）就从头记
import SnugCore

package struct CrossDeskLaunchDisplays: Sendable {
    /// 每一格此刻推哪块屏（格号 → 屏）：启动时认到的是初值，之后某格改推别的屏跟着改；
    /// 还没读到（刚启动还没认、启动那段已滚动掉、一块都没认到）为 nil
    package private(set) var slots: [Int: DisplayID]?

    package init() {}

    /// 各格推的屏（去重）；还没读到为 nil
    package var displays: Set<DisplayID>? { slots.map { Set($0.values) } }

    package mutating func take(_ line: Substring) {
        if let parsed = CrossDeskLogLine(line) { take(parsed) }
    }

    package mutating func take(_ line: CrossDeskLogLine) {
        switch line.event {
        case .started: slots = nil
        case .displayFound(let index, let display, _): slots = (slots ?? [:]).merging([index: display]) { $1 }
        case .displayRemapped(let slot, let display): slots?[slot] = display
        case .sharingBegan, .sharingEnded, .lastControllerLeft: break
        }
    }

    /// 此刻选得到的屏（online：系统此刻在线的全部屏）；还没读到为 nil。格子推的屏还在线的都选得到；
    /// 没格子推的新屏，不多于推着已下线屏的格就按序号落上去，也选得到。多了就一律算选不到：
    /// 哪块落在哪格看系统的排序，Snug 不知道，宁可多报（实测 Snug 的屏总排第 0，换编号的那块落回原来那格）
    package func reachable(online: Set<DisplayID>) -> Set<DisplayID>? {
        slots.map { slots in
            let held = Set(slots.values)
            let vacant = slots.values.filter { !online.contains($0) }.count
            return online.subtracting(held).count <= vacant ? online : held.intersection(online)
        }
    }

    /// CrossDesk 换了进程（重启、退了又开）：新进程启动那几句读到之前，旧的不算
    package mutating func restarted() { slots = nil }
}
