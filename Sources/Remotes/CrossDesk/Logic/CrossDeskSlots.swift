// CrossDesk 各格此刻推哪块屏、此刻选不到哪几块。它只在启动时认一次屏（抓屏模块初始化时），认到几块就有几格，
// 之后加的屏没有格子。开始推某一格时先按这格记的编号找，找不到就换成系统此刻屏幕列表里同一序号的那块（CrossDesk 1.7.7；
// 11-23 实测 Snug 重启换了编号，日志 display mapping refreshed: slot=0, old_id=24, new_id=25，照样推到新屏）。
// 推着的屏被撤掉时，约 2 秒后那格自动改推别的屏（同一句日志，11-23 实测落到内建屏上），那格就被占了。
// 从日志里跟着读：系统部分把新追加的行一行行交进来，遇到实例开头（Logger initialized）就从头记
import SnugCore

package struct CrossDeskSlots: Sendable {
    /// 格号 → 此刻推的屏：启动时认到的是初值，之后某格改推别的屏跟着改；
    /// 还没读到（刚启动还没认、启动那段已滚动掉、一块都没认到）为 nil
    package private(set) var displays: [Int: DisplayID]?

    package init() {}

    package mutating func take(_ line: Substring) {
        if let parsed = CrossDeskLogLine(line) { take(parsed) }
    }

    package mutating func take(_ line: CrossDeskLogLine) {
        switch line.event {
        case .started: displays = nil
        case .displayFound(let index, let display, _): displays = (displays ?? [:]).merging([index: display]) { $1 }
        case .displayRemapped(let slot, let display): displays?[slot] = display
        case .sharingBegan, .sharingEnded, .lastControllerLeft: break
        }
    }

    /// 此刻在线、CrossDesk 却选不到的屏；没读到格子为 nil。格子推的屏还在线的都选得到；没格子推的新屏，
    /// 不多于推着已下线屏的格时按序号落上去，选得到；多了哪块落哪格看系统排序，Snug 不知道，宁可都算选不到
    package func unreachable(online: Set<DisplayID>) -> Set<DisplayID>? {
        displays.map { slots in
            let fresh = online.subtracting(slots.values)
            let vacant = slots.values.filter { !online.contains($0) }.count
            return fresh.count <= vacant ? [] : fresh
        }
    }

    /// 写进日志、诊断的说法：「第 0 格 #29、第 1 格 #1」
    package var summary: String? {
        displays.map { $0.sorted { $0.key < $1.key }.map { "第 \($0.key) 格 #\($0.value)" }.joined(separator: "、") }
    }
}
