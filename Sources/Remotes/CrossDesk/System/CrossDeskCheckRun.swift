// --check-remote crossdesk [小时]：CrossDesk 兼容自检（scripts/snug remote-check crossdesk 调）。收集事实交给 CrossDeskCheck 判定、打出报告，
// 并把原始材料写进 ~/Library/Logs/Snug-crossdesk-check/（每次覆盖，见 RemoteCheckTools）：这段时间 CrossDesk 和 Snug 的日志、
// CrossDesk 的程序里找没找到 Snug 认的那几句、此刻的进程与电源断言、此刻的屏。只读：不碰 CrossDesk、不碰屏幕
import AppKit
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package enum CrossDeskCheckRun {
    package static func run(hours: Int) -> Int32 {
        let now = Date()
        let since = now.addingTimeInterval(-TimeInterval(hours) * 3600)
        let zone = TimeZone.current
        var files: [String: String] = [:]

        let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID)
        let version = bundle.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let sought = [CrossDeskRemote.sharingAssertion] + CrossDeskLogLine.phrases
        let scan = bundle.map { RemoteCheckTools.scanBundle($0, for: sought.reduce(into: [:]) { $0[$1] = Data($1.utf8) }) }
        let processes = CrossDeskHost.processes().map(\.processIdentifier)
        var sharingNow: [Int32]?
        var assertionNote: String
        do {
            sharingNow = CrossDeskRemote.sharingOwners(in: try CrossDeskHost.assertions())
            assertionNote = CrossDeskRemote.observation(sharing: sharingNow).evidence
        } catch {
            assertionNote = "电源断言查不了：\(error)"
        }
        files["crossdesk-program.txt"] = ([bundle.map { "CrossDesk：\($0.path)（\(version ?? "版本未知")）" } ?? "CrossDesk：没装"]
            + sought.map { "「\($0)」：\(scan?.hits[$0]?.joined(separator: "、") ?? "没找到")" }
            + ["进程：\(processes.isEmpty ? "没在运行" : processes.map(String.init).joined(separator: "、"))", assertionNote]).joined(separator: "\n")

        let log = CrossDeskLogs.lines()
        if let log { files["crossdesk.log"] = CrossDeskCheck.recent(log, since: since, in: zone).joined(separator: "\n") }
        let snugLines = RemoteCheckTools.snugLog()
        files["snug.log"] = SnugLogDigest.recent(snugLines, since: since).joined(separator: "\n")
        files["displays.txt"] = RemoteCheckTools.displayLines().joined(separator: "\n")

        let facts = CrossDeskCheck.Facts(hours: hours, since: since, version: version, processes: processes,
                                         foundInProgram: Set(scan?.hits.keys.map { $0 } ?? []), sharingNow: sharingNow, log: log, timeZone: zone,
                                         snugLog: snugLines.map(String.init), onlineDisplays: Set(Screens.online() ?? []),
                                         onlineSnugDisplays: RemoteCheckTools.onlineSnugDisplays())
        return RemoteCheckTools.conclude(CrossDeskCheck.evaluate(facts), remote: CrossDeskRemote.identity, hours: hours, at: now, files: files)
    }
}
