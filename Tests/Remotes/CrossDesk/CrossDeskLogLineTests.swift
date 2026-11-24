import Foundation
import RemoteCrossDesk
import Testing

/// 取自本机 CrossDesk 的日志（1.7.6、1.7.7 两版写法相同；1.7.7 的源文件行号变了，不影响）
private let lines = """
[2026-11-23 18:52:52.680] [crossdesk] [info] Logger initialized
[2026-11-23 18:52:52.680] [crossdesk] [info] Build identity: CrossDesk=acf678d (clean) MiniRTC=1a2b3c4 (clean)
[2026-11-23 18:52:52.825] [crossdesk] [info] [screen_capturer_sck_impl.mm:426] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
[2026-11-23 18:52:52.825] [crossdesk] [info] [screen_capturer_sck_impl.mm:426] macOS display discovered: index=1, display_id=3, name='JU24F160L'
[2026-11-23 09:03:53.951] [crossdesk] [info] [session_device_manager.cpp:345] Start screen capturer, show cursor: false
[2026-11-23 09:03:53.951] [crossdesk] [info] [screen_sharing_power.cpp:238] Requested display and system idle-sleep inhibition for screen sharing
[2026-11-23 09:10:08.951] [crossdesk] [info] [connection_runtime.cpp:236] Last remote controller disconnected; recovering privacy, reason=connection_closed
[2026-11-23 09:10:18.480] [crossdesk] [info] [screen_sharing_power.cpp:241] Released screen sharing power inhibitors
[2026-11-23 20:58:13.231] [crossdesk] [info] [screen_capturer_sck_impl.mm:649] macOS display mapping refreshed: slot=0, old_id=27, new_id=1, stream='Display1'
[2026-11-23 07:18:28.521] [crossdesk] [error] [config_center.cpp:195] Failed to write configuration: /Users/someone/.cache/CrossDesk/config.ini
""".split(separator: "\n")

@Suite("CrossDesk 日志里 Snug 认的几句")
struct CrossDeskLogLineTests {
    @Test("认出实例开头、启动时认到的屏、共享断言的建和放、最后一台断开、某一格改推别的屏；别的句子不认")
    func events() {
        let events = lines.map { CrossDeskLogLine($0)?.event }
        #expect(events == [
            .started, nil,
            .displayFound(index: 0, display: 1, name: "Built-in Retina Display"), .displayFound(index: 1, display: 3, name: "JU24F160L"),
            nil, .sharingBegan, .lastControllerLeft, .sharingEnded, .displayRemapped(slot: 0, display: 1), nil,
        ])
    }

    @Test("别的 logger、没写完的半行、时间戳不对、屏的写法残缺：都不认", arguments: [
        "[2026-11-23 09:03:53.951] [minirtc] [info] Logger initialized",
        "[2026-11-23 09:03:53.951] [crossdesk] [info] [screen_sharing_power.cpp:238] Requested display and system idle-sleep inhibition for scr",
        "[2026-11-23 09:03:53] [crossdesk] [info] Logger initialized",
        "2026-11-23 09:03:53.951 [crossdesk] [info] Logger initialized",
        "[2026-11-23 18:52:52.825] [crossdesk] [info] [x.mm:1] macOS display discovered: index=0, display_id=1, name='",
        "[2026-11-23 18:52:52.825] [crossdesk] [info] [x.mm:1] macOS display discovered: index=0, display_id=, name='A'",
        "[2026-11-23 18:52:52.825] [crossdesk] [info] [x.mm:1] macOS display discovered: index=0, name='A'",
        "[2026-11-23 20:58:13.231] [crossdesk] [info] [x.mm:1] macOS display mapping refreshed: slot=0, old_id=27, new_id=, stream='Display1'",
        "[2026-11-23 20:58:13.231] [crossdesk] [info] [x.mm:1] macOS display mapping refreshed: slot=, old_id=27, new_id=1, stream='Display1'",
    ])
    func rejects(line: String) {
        #expect(CrossDeskLogLine(line[...]) == nil)
    }

    @Test("时间戳按给定时区读成时刻，带毫秒")
    func date() throws {
        let line = try #require(CrossDeskLogLine(lines[5]))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = try #require(line.date(in: shanghai))
        #expect(abs(date.timeIntervalSince1970 - 1_795_395_833.951) < 0.0005)
    }

    @Test("最近一个实例：从最后一个 Logger initialized 起；一个都没有就是全部")
    func lastInstance() {
        let parsed = lines.compactMap { CrossDeskLogLine($0) }
        let restarted = parsed + [CrossDeskLogLine(lines[0])!, CrossDeskLogLine(lines[3])!]
        #expect(CrossDeskLogLine.lastInstance(restarted).map(\.event) == [.started, .displayFound(index: 1, display: 3, name: "JU24F160L")])
        let rotated = Array(parsed.dropFirst())
        #expect(CrossDeskLogLine.lastInstance(rotated).count == rotated.count)
    }
}
