// 远控兼容自检（--check-remote）各家共用的取证工具：读 Snug 自己的日志、扫远控包里的程序、此刻在线的屏、写取证材料、收尾出报告。
// 判定在各家的纯逻辑目标里（UU 见 UUCheck，CrossDesk 见 CrossDeskCheck），条目与报告的写法见 SnugCore 的 RemoteCheck
import CoreGraphics
import Foundation
import SnugCore

@MainActor
public enum RemoteCheckTools {
    /// Snug 日志的原文，滚动过的旧日志在前（见 FileLogSink），读不到的跳过
    public static func snugLog() -> [Substring] {
        let current = SnugPaths.standard.logFile
        return [FileLogSink.rotatedURL(of: current), current].flatMap { url -> [Substring] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n")
        }
    }

    /// 包里的 Mach-O 程序（包内路径，排好序），以及每个要找的字节串出现在哪些程序里。
    /// 按原始字节找，不依赖 otool、strings：框架的加载路径、代码里写死的字符串都能这样认
    public struct BundleScan: Sendable {
        public var programs: [String]
        public var hits: [String: [String]]
    }

    public static func scanBundle(_ bundle: URL, for needles: [String: Data]) -> BundleScan {
        var scan = BundleScan(programs: [], hits: [:])
        let walker = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: url, options: .alwaysMapped), isMachO(data) else { continue }
            let path = String(url.path.dropFirst(bundle.path.count + 1))
            scan.programs.append(path)
            for (name, needle) in needles where data.range(of: needle) != nil { scan.hits[name, default: []].append(path) }
        }
        scan.programs.sort()
        scan.hits = scan.hits.mapValues { $0.sorted() }
        return scan
    }

    /// 此刻在线的 Snug 的屏：设为主屏的那块常驻，建屏的日志可能早在回看之前
    public static func onlineSnugDisplays() -> Set<DisplayID> {
        Set((Screens.online() ?? []).filter { CGDisplayVendorNumber($0) == ScreenSpec.vendorID })
    }

    /// 此刻在线的屏，一行一块
    public static func displayLines() -> [String] {
        (Screens.online() ?? []).map { id in
            let mine = CGDisplayVendorNumber(id) == ScreenSpec.vendorID ? "（Snug 的屏）" : ""
            return "  #\(id) \(Screens.name(of: id))\(mine) \(DisplayMode.describe(id))"
        }
    }

    /// 打出报告，把报告连同材料写进 ~/Library/Logs/Snug-<日志名小写>-check/（每次覆盖），有一项不通过以 1 退出
    public static func conclude(_ items: [RemoteCheck.Item], remote: RemoteIdentity, hours: Int, at date: Date,
                                files: [String: String]) -> Int32 {
        let report = RemoteCheck.report(items, remote: remote, hours: hours, at: date)
        print(report)
        print("")
        print(writeEvidence(files.merging(["report.txt": report]) { _, new in new }, remote: remote))
        return RemoteCheck.exitCode(items)
    }

    /// 整个目录换成这次的材料；写不进去时说明原因（报告已经打出来了，不因此失败）
    private static func writeEvidence(_ files: [String: String], remote: RemoteIdentity) -> String {
        let fm = FileManager.default
        let evidence = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Snug-\(remote.logName.lowercased())-check")
        do {
            if fm.fileExists(atPath: evidence.path) { try fm.removeItem(at: evidence) }
            try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
            for (name, content) in files {
                try Data(content.utf8).write(to: evidence.appendingPathComponent(name))
            }
            return "取证材料：\(evidence.path)（\(files.keys.sorted().joined(separator: "、"))）"
        } catch {
            return "取证材料写不进 \(evidence.path)：\(error)"
        }
    }

    private static func isMachO(_ data: Data) -> Bool {
        let magics: [[UInt8]] = [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE], [0xCA, 0xFE, 0xBA, 0xBF]]
        return data.count >= 4 && magics.contains { data.prefix(4).elementsEqual($0) }
    }
}
