// --check-remote uu [小时]：UU远程 兼容自检（scripts/snug remote-check uu 调）。收集事实交给 UUCheck 判定、打出报告，
// 并把原始材料写进 ~/Library/Logs/Snug-uu-check/（每次覆盖，见 RemoteCheckTools）：UU 的推流日志、上一次远程前后 UURemoteServer 的全部日志、
// 这段时间的 Snug 日志、UU 的界面树、哪些程序链接了抓屏与编码框架。哪项不对直接看材料，不用再一步步复现。
// 只读：不点 UU、不碰屏幕
import AppKit
import RemoteUU
import SnugCore
import SnugSystem

@MainActor
package enum UUCheckRun {
    /// 上一次远程的原始日志从开始前这么久取起，最多取到开始后这么久（远程开头的连入、切屏最要紧，整场太长）
    static let sessionLead: TimeInterval = 10
    static let sessionSpan: TimeInterval = 300

    package static func run(hours: Int) -> Int32 {
        let now = Date()
        let since = now.addingTimeInterval(-TimeInterval(hours) * 3600)
        var files: [String: String] = [:]

        let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: UURemote.bundleID)
        let version = bundle.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let needles = [UUCheck.captureFramework, UUCheck.encoderFramework].reduce(into: [String: Data]()) {
            $0[$1] = Data("/System/Library/Frameworks/\($1).framework/".utf8)
        }
        let scan = bundle.map { RemoteCheckTools.scanBundle($0, for: needles) }
        let servers = scan?.programs.filter { ($0 as NSString).lastPathComponent == UURemote.serverProcess } ?? []
        let linkers = scan?.hits ?? [:]
        files["uu-binaries.txt"] = ([bundle.map { "UU远程：\($0.path)（\(version ?? "版本未知")）" } ?? "UU远程：没装"]
            + linkers.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value.joined(separator: "、"))" }
            + ["\(UURemote.serverProcess)：\(servers.joined(separator: "、"))"]).joined(separator: "\n")

        let captureLog = showLog(["--last", "\(hours)h", "--predicate", CaptureLogParser.predicate])
        var capture: [CaptureLogRecord]?
        if let captureLog {
            var buffer = CaptureLogLineBuffer()
            capture = buffer.feed(Data(captureLog.utf8)) + buffer.finish()
            files["uu-capture.ndjson"] = captureLog
        }

        let snugLines = RemoteCheckTools.snugLog()
        let snug = SnugLogDigest(lines: snugLines, since: since, remote: UURemote.identity.logName)
        files["snug.log"] = SnugLogDigest.recent(snugLines, since: since).joined(separator: "\n")
        if let start = snug.sessionStarts.last {
            let end = min(snug.sessionEnds.first { $0 > start }.map { $0 + 15 } ?? now, start + sessionSpan)
            files["uu-server-last-session.ndjson"] = showLog(["--start", logTime(start - sessionLead), "--end", logTime(end),
                                                             "--predicate", "process == \"\(UURemote.serverProcess)\""])
        }

        let pid = UURemoteApp.pid()
        var table: ControllerTable?
        if AX.isTrusted, let pid {
            let windows = UUAccessibility.windows(pid: pid)
            table = windows.map(ControllerTable.init) ?? .unreadable
            files["uu-ax-tree.txt"] = windows.map { UUDump.treeLines($0).joined(separator: "\n") } ?? "读不到（UU 没有窗口、没响应，或界面超出遍历上限）"
        }
        files["displays.txt"] = RemoteCheckTools.displayLines().joined(separator: "\n")
        let server = UURemoteApp.serverPID().map { UUCheck.Server(pid: $0, start: processStart($0)) }

        let facts = UUCheck.Facts(hours: hours, since: since, version: version, appRunning: pid != nil, server: server,
                                  serverExecutables: servers, linkers: linkers, capture: capture, snugLog: snugLines.map(String.init),
                                  onlineSnugDisplays: RemoteCheckTools.onlineSnugDisplays(), controllersNow: table)
        return RemoteCheckTools.conclude(UUCheck.evaluate(facts), remote: UURemote.identity, hours: hours, at: now, files: files)
    }

    // MARK: 收集

    /// 进程启动的时刻（内核记的）；读不到为 nil
    private static func processStart(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// `log show … --style ndjson`；失败时在标准错误说明原因，返回 nil。
    /// 标准错误并进同一根管子：分两根依次读的话，一根写满会把另一根卡死；解析只认 JSON 行，混进来的提示不影响
    private static func showLog(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--style", "ndjson"] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("log show 启动失败：\(error)\n".utf8))
            return nil
        }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            FileHandle.standardError.write(Data("log show 失败（状态 \(process.terminationStatus)）：\(text.suffix(500))\n".utf8))
            return nil
        }
        return text
    }

    private static func logTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
