import AppKit
import RemoteCrossDesk
import SnugCore

@MainActor
package enum CrossDeskDiagnostics {
    package static func dump() -> Int32 {
        let host = CrossDeskRemoteAdapter.runningHost
        if let url = host?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID),
           let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            print("CrossDesk 版本：\(version)（验证过 \(CrossDeskRemote.verifiedVersion) 的日志格式）")
        } else {
            print("未找到 CrossDesk.app（\(CrossDeskRemote.bundleID)）")
        }
        let capture = host?.launchDate.flatMap { CrossDeskLogs.state(in: CrossDeskLogs.files(since: $0), since: $0) }
        let observation = CrossDeskRemote.observation(running: host != nil, capture: capture)
        print("会话观测：\(observation.evidence)")
        print("日志：\(CrossDeskLogs.directory.path)")
        return host != nil && capture != nil ? 0 : 1
    }

    package static func check(hours: Int) -> Int32 {
        let since = Date().addingTimeInterval(-Double(hours) * 3_600)
        let dumpStatus = dump()
        guard let events = CrossDeskLogs.recentEvents(since: since), !events.isEmpty else {
            print("⚠️ 最近 \(hours) 小时读不到 CrossDesk 会话信号")
            return 1
        }
        let starts = events.filter { $0 == .captureStarted }.count
        let ends = events.filter { $0 == .lastControllerLeft }.count
        let failures = events.filter { $0 == .captureFailed }.count
        print("最近 \(hours) 小时：抓屏启动 \(starts) 次，最后一台控制端断开 \(ends) 次，抓屏失败 \(failures) 次")
        let logFile = SnugPaths.standard.logFile
        if let log = try? String(contentsOf: logFile, encoding: .utf8) {
            let digest = SnugLogDigest(lines: log.split(separator: "\n"), since: since, remote: CrossDeskRemote.identity.logName)
            print("Snug 记录 CrossDesk 连入 \(digest.detections.count) 次")
        }
        if starts == 0 { print("ℹ️ 本时段没有抓屏启动记录，连入待下次核对") }
        return dumpStatus
    }
}
