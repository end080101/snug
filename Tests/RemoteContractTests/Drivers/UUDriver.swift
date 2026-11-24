import CoreGraphics
import Foundation
import RemoteUU
import SnugCore

/// UU：三路信号（覆盖窗口、控制端表格、推流日志）。推流屏走正式的推流状态（CaptureSessionState），不是直接填
struct UUDriver: RemoteDriver {
    let identity = UURemote.identity
    let namesControllers = true
    let reportsStreamedDisplay = true
    let injectorPath = "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"
    let appBundleID = UURemote.bundleID

    func idle() -> RemoteObservation {
        signals(.unrecognized, capture: [])
    }

    func unreadable() -> RemoteObservation {
        UUSignals(overlayVisible: false, controllers: .unreadable, captureActive: nil).observation(streamedDisplay: nil)
    }

    func connected(controllers: [String]) -> RemoteObservation {
        signals(.shown(controllers), capture: [.captureStarted])
    }

    func streaming(_ display: DisplayID) -> RemoteObservation {
        signals(.unrecognized, capture: [.displayDescribed(display), .captureStarted])
    }

    /// UU 随时认新屏（连上后建的屏也选得到），不报
    func reaching(launched: Set<DisplayID>, online: Set<DisplayID>) -> RemoteObservation? { nil }

    /// UU 把手指当鼠标左键：按下、拖动、抬起原样发过来
    func touchEvents(_ gesture: FingerGesture) -> [PointerEvent] {
        let p = CGPoint(x: 200, y: 400)
        let down = PointerEvent(.leftDown, at: p, time: 10)
        let drags = { (start: Double) in (1...6).map { PointerEvent(.leftDrag, at: CGPoint(x: 200, y: 400 + Double($0) * 15), time: start + Double($0) * 0.016) } }
        return switch gesture {
        case .tap: [down, PointerEvent(.leftUp, at: p, time: 10.08)]
        case .holdRelease: [down, PointerEvent(.leftUp, at: p, time: 10.7)]
        case .holdDrag: [down] + drags(10.6) + [PointerEvent(.leftUp, at: CGPoint(x: 200, y: 490), time: 10.8)]
        case .slide: [down] + drags(10) + [PointerEvent(.leftUp, at: CGPoint(x: 200, y: 490), time: 10.1)]
        }
    }

    /// 按顺序回放这几条推流事件，再在最后一条之后问推流状态
    private func signals(_ table: ControllerTable, capture events: [CaptureLogEvent]) -> RemoteObservation {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var state = CaptureSessionState()
        for (i, event) in events.enumerated() { state.apply(CaptureLogRecord(date: start + Double(i) * 0.1, event: event)) }
        let now = start + 1
        return UUSignals(overlayVisible: false, controllers: table, captureActive: state.isActive(at: now))
            .observation(streamedDisplay: state.streamingDisplay(at: now))
    }
}
