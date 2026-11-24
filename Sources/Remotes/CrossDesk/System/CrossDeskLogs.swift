// CrossDesk 的日志文件：spdlog 滚动，crossdesk.log 最新，crossdesk.1.log 到 .3 依次更旧（rd_log.cpp：5MB、留 3 份）
import Foundation

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

/// 跟着读 crossdesk.log 新追加的行：每拍看一眼文件，长了只读新长出来的那段；换了文件（滚动）从新文件开头读。
/// 头一次只读末尾 initialWindow 字节：CrossDesk 启动那几句通常就在里面，读不到也只是不提示
final class CrossDeskLogTail {
    static let initialWindow: UInt64 = 1 << 20
    private let url = CrossDeskLogs.directory.appendingPathComponent("crossdesk.log")
    private var file: UInt64?
    private var offset: UInt64 = 0
    /// 读到了一半的行（最后一个换行之后的字节）
    private var pending = Data()

    /// 新追加的完整的行；日志还没有、没变为空
    func poll() throws -> [Substring] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return [] }
        let id = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        var skipPartial = false
        if file == nil {
            offset = size > Self.initialWindow ? size - Self.initialWindow : 0
            skipPartial = offset > 0
        } else if id != file || size < offset {
            offset = 0
            pending = Data()
        }
        file = id
        guard size > offset else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var data = try handle.read(upToCount: Int(size - offset)) ?? Data()
        offset += UInt64(data.count)
        // 从文件中间开始读：头一行是半截，丢掉
        if skipPartial, let newline = data.firstIndex(of: 0x0A) { data = data[(newline + 1)...] }
        pending += data
        guard let last = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[..<last]
        pending = Data(pending[(last + 1)...])
        return String(decoding: complete, as: UTF8.self).split(separator: "\n")
    }
}

