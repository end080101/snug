// CrossDesk 日志里 Snug 认的几句。日志在 ~/Library/Logs/CrossDesk/crossdesk.log（spdlog，5MB 滚动，留 3 份旧的），
// 一行：[yyyy-MM-dd HH:mm:ss.SSS] [crossdesk] [级别] [源文件:行] 内容，时间是本机的本地时间，自己那句 Logger initialized 不带源文件。
// Snug 判在场不看日志（看电源断言，见 CrossDeskRemote）；日志只拿来自检（CrossDeskCheck）和认 CrossDesk 启动时看到了哪几块屏
import Foundation
import SnugCore

package struct CrossDeskLogLine: Equatable, Sendable {
    package enum Event: Equatable, Sendable {
        /// 一个 CrossDesk 实例写的第一句：实例的边界
        case started
        /// 启动时认到的一块屏。CrossDesk 只在启动时认屏，之后建的屏它选不到
        case displayFound(index: Int, display: DisplayID, name: String)
        /// 建了「共享桌面」的电源断言：开始被远程
        case sharingBegan
        /// 放了这条断言：停止抓屏（可能比最后一台断开晚几秒）
        case sharingEnded
        /// 最后一台控制端断开
        case lastControllerLeft
    }

    /// 原样的时间戳（本地时间）
    package var stamp: Substring
    package var event: Event

    /// 认的几句的固定开头：自检拿它们去 CrossDesk 的程序里找，找不到就是改了写法
    package static let started = "Logger initialized"
    package static let displayFound = "macOS display discovered: index="
    package static let sharingBegan = "Requested display and system idle-sleep inhibition for screen sharing"
    package static let sharingEnded = "Released screen sharing power inhibitors"
    package static let lastControllerLeft = "Last remote controller disconnected;"
    package static let phrases = [started, displayFound, sharingBegan, sharingEnded, lastControllerLeft]

    /// 认不出的行（别的句子、没写完的半行、别的 logger）为 nil
    package init?(_ line: Substring) {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<close]
        guard stamp.utf8.count == 23 else { return nil }
        var message = line[line.index(after: close)...]
        let logger = " [crossdesk] ["
        guard message.hasPrefix(logger) else { return nil }
        message = message.dropFirst(logger.count)
        guard let levelEnd = message.range(of: "] ") else { return nil }
        message = message[levelEnd.upperBound...]
        if message.first == "[", let sourceEnd = message.range(of: "] ") { message = message[sourceEnd.upperBound...] }
        guard let event = Self.event(message) else { return nil }
        self.stamp = stamp
        self.event = event
    }

    /// 时间戳按 timeZone 读成时刻。夏令时回拨的那一小时有两个读法，取前一个：只影响自检里的对照
    package func date(in timeZone: TimeZone = .current) -> Date? { Self.date(stamp: stamp, in: timeZone) }

    /// 任意一行（认不认得这句都行）的时刻；不是以时间戳开头的行（多行报错的续行）为 nil
    package static func date(ofLine line: Substring, in timeZone: TimeZone = .current) -> Date? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        return date(stamp: line[line.index(after: line.startIndex)..<close], in: timeZone)
    }

    private static func date(stamp: Substring, in timeZone: TimeZone) -> Date? {
        let digits = stamp.split(whereSeparator: { "- :.".contains($0) }).compactMap { Int($0) }
        guard stamp.utf8.count == 23, digits.count == 7 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: digits[0], month: digits[1], day: digits[2], hour: digits[3], minute: digits[4], second: digits[5])
        return calendar.date(from: parts).map { $0 + Double(digits[6]) / 1000 }
    }

    /// 最近一个实例写的那几行：从尾部往前找最近的 started，找不到（滚动掉了）就是全部
    package static func lastInstance(_ lines: [CrossDeskLogLine]) -> ArraySlice<CrossDeskLogLine> {
        lines[(lines.lastIndex { $0.event == .started } ?? lines.startIndex)...]
    }

    private static func event(_ message: Substring) -> Event? {
        switch message {
        case started: return .started
        case sharingBegan: return .sharingBegan
        case sharingEnded: return .sharingEnded
        case _ where message.hasPrefix(lastControllerLeft): return .lastControllerLeft
        case _ where message.hasPrefix(displayFound): return display(message.dropFirst(displayFound.count))
        default: return nil
        }
    }

    /// 「0, display_id=1, name='Built-in Retina Display'」
    private static func display(_ rest: Substring) -> Event? {
        let idKey = ", display_id=", nameKey = ", name='"
        guard let idRange = rest.range(of: idKey), let nameRange = rest.range(of: nameKey, range: idRange.upperBound..<rest.endIndex),
              let index = Int(rest[..<idRange.lowerBound]), let display = DisplayID(rest[idRange.upperBound..<nameRange.lowerBound]),
              nameRange.upperBound < rest.endIndex, rest.last == "'" else { return nil }
        return .displayFound(index: index, display: display, name: String(rest[nameRange.upperBound..<rest.index(before: rest.endIndex)]))
    }
}
