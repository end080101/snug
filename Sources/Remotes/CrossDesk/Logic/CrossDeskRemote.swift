import SnugCore

package enum CrossDeskRemote {
    package static let bundleID = "cn.crossdesk.app"
    package static let verifiedVersion = "v1.7.6-20261112"
    package static let identity = RemoteIdentity(logName: "CrossDesk", displayName: "CrossDesk",
                                                bundleIDs: [bundleID], injector: nil)

    package static func observation(running: Bool, capture: Bool?) -> RemoteObservation {
        let status = capture.map { $0 ? "是" : "否" } ?? "未知"
        return RemoteObservation(present: running && capture == true, controllers: [], streamedDisplay: nil,
                                 evidence: "进程=\(running ? "是" : "否") capture=\(status)")
    }
}
