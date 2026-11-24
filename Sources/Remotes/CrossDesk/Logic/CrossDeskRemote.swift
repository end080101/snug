import SnugCore

package enum CrossDeskRemote {
    package static let bundleID = "cn.crossdesk.app"
    package static let verifiedVersion = "v1.7.6-20261112"
    /// 被远程时注入鼠标事件的进程：主程序自己（CGEventPost，事件带 CROSSDES 记号）
    package static let injectorProcess = "CrossDesk"
    package static let identity = RemoteIdentity(logName: "CrossDesk", displayName: "CrossDesk", bundleIDs: [bundleID],
                                                injector: InjectedEventSource(executableName: injectorProcess), normalizer: CrossDeskTouch.self)

    package static func observation(running: Bool, capture: Bool?) -> RemoteObservation {
        let status = capture.map { $0 ? "是" : "否" } ?? "未知"
        return RemoteObservation(present: running && capture == true, controllers: [], streamedDisplay: nil,
                                 evidence: "进程=\(running ? "是" : "否") capture=\(status)")
    }
}
