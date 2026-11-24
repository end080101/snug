import Foundation
import RemoteCrossDesk

enum CrossDeskLogs {
    struct FileStamp: Equatable, Sendable {
        let url: URL
        let size: Int
        let modified: Date
        let identifier: UInt64
    }

    static let directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appending(path: "Library/Logs/CrossDesk", directoryHint: .isDirectory)

    /// spdlog keeps the current file and up to three rotated copies, newest first.
    static func files(since date: Date) -> [FileStamp] {
        (0...3).compactMap { index in
            let name = index == 0 ? "crossdesk.log" : "crossdesk.\(index).log"
            let file = directory.appending(path: name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  let modified = attributes[.modificationDate] as? Date, modified >= date,
                  let identifier = attributes[.systemFileNumber] as? NSNumber else { return nil }
            return FileStamp(url: file, size: size.intValue, modified: modified, identifier: identifier.uint64Value)
        }
    }

    static func recentEvents(since date: Date) -> [CrossDeskLog.Event]? {
        let files = files(since: date)
        guard !files.isEmpty else { return nil }
        let cutoff = timestamp(date)
        var events: [CrossDeskLog.Event] = []
        for file in files.reversed() {
            guard let log = read(file.url) else { return nil }
            let complete = log[..<(log.lastIndex(of: "\n") ?? log.startIndex)]
            for line in complete.split(separator: "\n") {
                guard let record = CrossDeskLog.record(line), record.timestamp >= cutoff[...] else { continue }
                events.append(record.event)
            }
        }
        return events
    }

    private static func read(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        // A partially written multibyte character at the end must not hide earlier records.
        return String(decoding: data, as: UTF8.self)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
