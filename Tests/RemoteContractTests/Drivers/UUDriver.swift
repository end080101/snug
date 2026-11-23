import Foundation
import RemoteUU
import SnugCore

/// UU：三路信号（覆盖窗口、控制端表格、推流日志）。推流屏走正式的推流状态（CaptureSessionState），不是直接填
struct UUDriver: RemoteDriver {
    let identity = UURemote.identity
    let namesControllers = true
    let reportsStreamedDisplay = true
    let injectorPath: String? = "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"
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
