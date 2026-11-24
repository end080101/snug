// CrossDesk 的日志文件：spdlog 滚动，crossdesk.log 最新，crossdesk.1.log 到 .3 依次更旧（rd_log.cpp：5MB、留 3 份）
import Foundation
import RemoteCrossDesk

enum CrossDeskLogs {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CrossDesk")

    /// 几份日志的原文按时间顺序拼起来（旧的在前）；一份都读不到为 nil。还没滚动出来的那几份不算读不到，有却读不了的在标准错误说明
    static func lines() -> [String]? {
        var lines: [String] = []
        var read = false
        for index in stride(from: 3, through: 0, by: -1) {
            let url = directory.appendingPathComponent(index == 0 ? "crossdesk.log" : "crossdesk.\(index).log")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                // 末尾可能有写了一半的多字节字符：按字节解码，不让它连累前面的行
                lines += String(decoding: try Data(contentsOf: url), as: UTF8.self).split(separator: "\n").map(String.init)
                read = true
            } catch {
                FileHandle.standardError.write(Data("读不了 \(url.path)：\(error)\n".utf8))
            }
        }
        return read ? lines : nil
    }
}

/// 跟着读 crossdesk.log 新追加的行：每拍看一眼文件，从哪读到哪、怎么拼行由 CrossDeskLogFollower 定，这里只读文件
struct CrossDeskLogTail {
    private let url = CrossDeskLogs.directory.appendingPathComponent("crossdesk.log")
    private var follower = CrossDeskLogFollower()

    /// 新追加的完整的行；日志还没有、没变为空
    mutating func poll() throws -> [Substring] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return [] }
        let id = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        guard let range = follower.range(file: id, size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0) else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: range.lowerBound)
        return follower.lines(from: try handle.read(upToCount: Int(range.count)) ?? Data())
    }
}
