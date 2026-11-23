import AppKit
import RemoteCrossDesk
import SnugCore

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity

    private var hostLaunch: Date?
    private var files: [CrossDeskLogs.FileStamp]?
    private var capture: Bool?
    private var pendingRead: Task<Void, Never>?

    package init() {}

    package func start() {}

    package func stop() {
        pendingRead?.cancel()
        pendingRead = nil
        hostLaunch = nil
        files = nil
        capture = nil
    }

    package func sample(wallClock: Date) -> RemoteObservation {
        guard let launch = Self.runningHost?.launchDate else {
            stop()
            return CrossDeskRemote.observation(running: false, capture: nil)
        }
        if launch != hostLaunch {
            stop()
            hostLaunch = launch
        }
        if pendingRead == nil {
            let previous = files
            pendingRead = Task { [weak self] in
                let update = await Task.detached(priority: .utility) { () -> (files: [CrossDeskLogs.FileStamp], state: Bool?)? in
                    let current = CrossDeskLogs.files(since: launch)
                    guard current != previous else { return nil }
                    return (current, CrossDeskLogs.state(in: current, since: launch))
                }.value
                guard !Task.isCancelled, let self else { return }
                if let update {
                    // Retry an unreadable log, even if its metadata stayed the same.
                    files = update.state == nil ? nil : update.files
                    capture = update.state
                }
                pendingRead = nil
            }
        }
        return CrossDeskRemote.observation(running: true, capture: capture)
    }

    static var runningHost: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: CrossDeskRemote.bundleID)
            .filter { !$0.isTerminated && $0.launchDate != nil }
            .min { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }
    }
}
