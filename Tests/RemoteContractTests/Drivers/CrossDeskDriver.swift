import CoreGraphics
import RemoteCrossDesk
import SnugCore

struct CrossDeskDriver: RemoteDriver {
    let identity = CrossDeskRemote.identity
    let namesControllers = false
    let reportsStreamedDisplay = false
    let injectorPath = "/Applications/CrossDesk.app/Contents/MacOS/CrossDesk"
    let appBundleID = CrossDeskRemote.bundleID

    func idle() -> RemoteObservation {
        CrossDeskRemote.observation(sharing: CrossDeskRemote.sharingOwners(in: [352: ["Powerd - Prevent sleep while display is on"], 78275: []]))
    }

    func unreadable() -> RemoteObservation {
        CrossDeskRemote.observation(sharing: nil)
    }

    func connected(controllers: [String]) -> RemoteObservation {
        CrossDeskRemote.observation(sharing: CrossDeskRemote.sharingOwners(in: [352: ["Powerd - Prevent sleep while display is on"],
                                                                               78275: [CrossDeskRemote.sharingAssertion, CrossDeskRemote.sharingAssertion]]))
    }

    func streaming(_ display: DisplayID) -> RemoteObservation {
        connected(controllers: [])
    }

    /// CrossDesk 只在启动时认屏：认到的从日志里跟着读
    func reaching(launched: Set<DisplayID>, online: Set<DisplayID>) -> RemoteObservation? {
        var slots = CrossDeskSlots()
        slots.take("[2026-11-23 18:52:52.680] [crossdesk] [info] Logger initialized")
        for (index, id) in launched.sorted().enumerated() {
            slots.take("[2026-11-23 18:52:52.825] [crossdesk] [info] [x.mm:426] macOS display discovered: index=\(index), display_id=\(id), name='屏'")
        }
        return CrossDeskRemote.observation(sharing: [], unreachable: slots.unreachable(online: online))
    }

    /// iOS 选「绝对鼠标」时：点、长按带一个手指处的移动，滑动只发不按键的移动。
    /// 滑动前先来一个孤立的移动，开头跳到 80 点开外：整理据此认出是绝对鼠标
    func touchEvents(_ gesture: FingerGesture) -> [PointerEvent] {
        let p = CGPoint(x: 200, y: 400)
        let touch = [PointerEvent(.move, at: p, time: 10), PointerEvent(.leftDown, at: p, time: 10.0005)]
        let moves = { (start: Double) in (1...6).map { CGPoint(x: 200, y: 400 + Double($0) * 15) }.enumerated().map { PointerEvent(.move, at: $1, time: start + Double($0) * 0.016) } }
        return switch gesture {
        case .tap: touch + [PointerEvent(.leftUp, at: p, time: 10.001)]
        case .holdRelease: touch + [PointerEvent(.leftUp, at: p, time: 10.4)]
        case .holdDrag: touch + moves(10.05).map { PointerEvent(.leftDrag, at: $0.location, time: $0.time) } + [PointerEvent(.leftUp, at: CGPoint(x: 200, y: 490), time: 10.3)]
        case .slide: [PointerEvent(.move, at: CGPoint(x: 100, y: 100), time: 9), PointerEvent(.move, at: p, time: 10)] + moves(10.016)
        }
    }
}
