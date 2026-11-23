import Foundation

package enum CrossDeskLog {
    package struct Record {
        package let timestamp: Substring
        package let event: Event
    }

    package enum Event {
        case initialized, captureStarted, captureFailed, captureStopped, lastControllerLeft

        var capturing: Bool { self == .captureStarted }
    }

    package static func captureState(in log: String, since: String) -> Bool? {
        // spdlog flushes complete lines. A write concurrent with this read can leave a partial final line.
        guard let lastNewline = log.lastIndex(of: "\n") else { return nil }
        var remaining = log[..<lastNewline]
        while let newline = remaining.lastIndex(of: "\n") {
            let line = remaining[remaining.index(after: newline)...]
            if let record = record(line), record.timestamp >= since[...] { return record.event.capturing }
            remaining = remaining[..<newline]
        }
        guard let record = record(remaining), record.timestamp >= since[...] else { return nil }
        return record.event.capturing
    }

    package static func record(_ line: Substring) -> Record? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let timestamp = line[line.index(after: line.startIndex)..<close]
        guard timestamp.utf8.count == 23 else { return nil }
        var message = line[line.index(after: close)...]
        let logger = " [crossdesk] ["
        guard message.hasPrefix(logger) else { return nil }
        message = message.dropFirst(logger.count)
        guard let levelEnd = message.range(of: "] ") else { return nil }
        message = message[levelEnd.upperBound...]
        // LOG_INFO supplies a source location. The logger's own initialization message has none.
        if message.first == "[", let sourceEnd = message.range(of: "] ") {
            message = message[sourceEnd.upperBound...]
        }
        let event: Event
        switch message {
        case "Logger initialized": event = .initialized
        case "Start screen capturer, show cursor: true", "Start screen capturer, show cursor: false": event = .captureStarted
        case "Stop screen capturer": event = .captureStopped
        case _ where message.hasPrefix("Last remote controller disconnected;"): event = .lastControllerLeft
        case _ where message.hasPrefix("Start screen capturer failed: "): event = .captureFailed
        default: return nil
        }
        return Record(timestamp: timestamp, event: event)
    }
}
