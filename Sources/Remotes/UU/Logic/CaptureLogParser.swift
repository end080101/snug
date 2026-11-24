// 解析 `log stream --style ndjson` 里 UURemoteServer 抓屏的几类事件（屏的描述、抓屏流的登记输出、开推、停、释放），交给 CaptureStreams。
// 这些行来自 ScreenCaptureKit 的调试日志，格式不是公开接口，所以只认几条稳定的关键字，
// 认不出的行一律忽略。格式变了，认不出开始事件时推流信号缺席，停止和释放都认不出时推流会一直显示在进行，后果见 ConnectionTracker。
// ScreenCaptureKit 自己停流时还会打一句不带地址的「Stopping stream due to」，紧跟着每路流都有带地址的停止（2026-11-12 四次都是），不另外认
import Foundation
import SnugCore

/// stream：SCStream 对象的地址。同一进程里同时开着的流各不相同，停了以后可能给新开的流用
package enum CaptureLogEvent: Equatable, Sendable {
    /// -[SCDisplay initWithDict:] … displayID=N：ScreenCaptureKit 描述了一块屏。
    /// UU 枚举全部屏幕时每块都会出现一次，为要推的那块建过滤器时再出现一次，紧接着推流开始
    case displayDescribed(DisplayID)
    /// -[SCStream addStreamOutput:type:…] 0x… type=N，N 不是 0（画面）而是 1（声音）或 2（麦克风）：这路流带声音
    case soundAdded(stream: UInt64)
    /// -[SCStream startCaptureWithCompletionHandler:] 0x…
    case captureStarted(stream: UInt64)
    /// -[SCStream stopCaptureWithCompletionHandler:] 0x…
    case captureStopped(stream: UInt64)
    /// -[SCStream dealloc] 0x…：这路流的对象释放了。紧跟在停之后（11-23 六路流都是 6～36 毫秒），停的那句没记到时靠它收尾
    case released(stream: UInt64)
}

package struct CaptureLogRecord: Equatable, Sendable {
    package let date: Date
    package let event: CaptureLogEvent
    /// 打这条日志的 UURemoteServer 进程号；读不到为 nil
    package let processID: pid_t?

    package init(date: Date, event: CaptureLogEvent, processID: pid_t? = nil) {
        self.date = date
        self.event = event
        self.processID = processID
    }
}

package struct CaptureLogParser {
    /// classify 认的几类行都含其中一个词。log 子进程按它过滤：Snug 少收、少解析，回看几个小时的日志也只有几百行
    static let keywords = ["SCDisplay initWithDict:", "CaptureWithCompletionHandler:]", "addStreamOutput:type:", "SCStream dealloc]"]
    /// `log stream` / `log show` 的 --predicate
    package static let predicate = "process == \"\(UURemote.serverProcess)\" AND ("
        + keywords.map { "eventMessage CONTAINS \"\($0)\"" }.joined(separator: " OR ") + ")"

    private let formatter: DateFormatter

    package init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // log 的 ndjson 时间戳形如 2026-11-12 19:01:43.417100-0800
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    }

    /// 一行 ndjson → 事件；不是 UURemoteServer 的、认不出的、非 JSON 的都返回 nil
    package func parse(line: String) -> CaptureLogRecord? {
        guard line.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = object["eventMessage"] as? String,
              let stamp = object["timestamp"] as? String,
              let date = formatter.date(from: stamp) else { return nil }
        if let process = object["processImagePath"] as? String, !process.hasSuffix("/" + UURemote.serverProcess) { return nil }
        let processID = (object["processID"] as? Int).flatMap(pid_t.init(exactly:))
        return Self.classify(message).map { CaptureLogRecord(date: date, event: $0, processID: processID) }
    }

    static func classify(_ message: String) -> CaptureLogEvent? {
        if message.contains("SCDisplay initWithDict:") {
            return token(after: "displayID=", in: message, \.isNumber).flatMap { DisplayID($0) }.map { .displayDescribed($0) }
        }
        // 只认方法名后面紧跟「:行号 0x地址」的那句：停流回调里的报错（…]_block_invoke_2…error=）、登记输出的收尾（…]:828）都不带地址
        guard let stream = token(after: " 0x", in: message, \.isHexDigit).flatMap({ UInt64($0, radix: 16) }) else { return nil }
        if message.contains("startCaptureWithCompletionHandler:]:") { return .captureStarted(stream: stream) }
        if message.contains("stopCaptureWithCompletionHandler:]:") { return .captureStopped(stream: stream) }
        if message.contains("SCStream dealloc]:") { return .released(stream: stream) }
        guard message.contains("addStreamOutput:type:"),
              let type = token(after: " type=", in: message, \.isNumber).flatMap({ Int($0) }) else { return nil }
        return type == 0 ? nil : .soundAdded(stream: stream)
    }

    /// key 之后连着的一串 kind 字符；没有 key 为 nil
    private static func token(after key: String, in message: String, _ kind: (Character) -> Bool) -> Substring? {
        message.range(of: key).map { message[$0.upperBound...].prefix(while: kind) }
    }
}

/// 把 log 子进程的输出切成行再解析：一行常被切在两块数据里，按字节攒到换行再解码（先解码会把切在中间的汉字解坏）
package struct CaptureLogLineBuffer {
    private var pending = Data()
    private let parser = CaptureLogParser()

    package init() {}

    package mutating func feed(_ data: Data) -> [CaptureLogRecord] {
        pending.append(data)
        var records: [CaptureLogRecord] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            if let r = parse(pending[pending.startIndex..<newline]) { records.append(r) }
            pending.removeSubrange(pending.startIndex...newline)
        }
        return records
    }

    /// 输出结束：最后一行可能没有换行
    package mutating func finish() -> [CaptureLogRecord] {
        defer { pending.removeAll() }
        return parse(pending).map { [$0] } ?? []
    }

    private func parse(_ line: Data) -> CaptureLogRecord? {
        parser.parse(line: String(decoding: line, as: UTF8.self))
    }
}
