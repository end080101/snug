// --dump-remote crossdesk：打印从 CrossDesk 读到的东西。--check-remote crossdesk：兼容自检。只读，不碰 CrossDesk、不碰屏幕
import AppKit
import RemoteCrossDesk
import SnugCore

@MainActor
package enum CrossDeskDiagnostics {
    package static func dump() -> Int32 {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID) {
            let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            print("CrossDesk：\(url.path)（版本 \(version ?? "未知")，上次核对的是 \(CrossDeskRemote.verifiedVersion)）")
        } else {
            print("CrossDesk：没装（按 \(CrossDeskRemote.bundleID) 找不到）")
        }
        let processes = CrossDeskHost.processes()
        print("进程：" + (processes.isEmpty ? "没在运行" : processes.map { app in
            let start = app.launchDate.map { "启动于 \($0.formatted(date: .omitted, time: .standard))" } ?? "没有启动时间（开机自启或看门狗拉起）"
            return "\(app.processIdentifier)（\(app.executableURL?.path ?? "路径读不到")，\(start)）"
        }.joined(separator: "；")))
        let owners: [Int32]?
        do {
            owners = CrossDeskRemote.sharingOwners(in: try CrossDeskHost.assertions())
        } catch {
            print("电源断言：查不了（\(error)）")
            owners = nil
        }
        print("会话观测：\(CrossDeskRemote.observation(sharing: owners).evidence)")
        print("日志：\(CrossDeskLogs.directory.path)")
        return owners == nil ? 1 : 0
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
