import RemoteCrossDesk
import SnugCore

struct CrossDeskDriver: RemoteDriver {
    let identity = CrossDeskRemote.identity
    let namesControllers = false
    let reportsStreamedDisplay = false
    let injectorPath: String? = nil
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

    private func observation(_ message: String) -> RemoteObservation {
        let line = "[2026-11-23 21:44:45.735] [crossdesk] [info] \(message)\n"
        return CrossDeskRemote.observation(running: true, capture: CrossDeskLog.captureState(in: line, since: "2026-11-23 21:44:06.000"))
    }
}
