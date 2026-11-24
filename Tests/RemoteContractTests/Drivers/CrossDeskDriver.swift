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
        observation("Logger initialized")
    }

    func unreadable() -> RemoteObservation {
        CrossDeskRemote.observation(running: true, capture: nil)
    }

    func connected(controllers: [String]) -> RemoteObservation {
        observation("Start screen capturer, show cursor: false")
    }

    func streaming(_ display: DisplayID) -> RemoteObservation {
        connected(controllers: [])
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

    private func observation(_ message: String) -> RemoteObservation {
        let line = "[2026-11-23 21:44:45.735] [crossdesk] [info] \(message)\n"
        return CrossDeskRemote.observation(running: true, capture: CrossDeskLog.captureState(in: line, since: "2026-11-23 21:44:06.000"))
    }
}
