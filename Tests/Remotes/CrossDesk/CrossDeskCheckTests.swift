import Foundation
import RemoteCrossDesk
import SnugCore
import Testing

/// 两份日志都是本机本地时间：用当前时区读，和正式运行一样
private let zone = TimeZone.current

private func at(_ clock: String) -> Date { CrossDeskLogLine.date(ofLine: "[2026-11-23 \(clock)]", in: zone)! }

private func crossdesk(_ clock: String, _ message: String) -> String {
    "[2026-11-23 \(clock)] [crossdesk] [info] [x.cpp:1] \(message)"
}

private let started = "[2026-11-23 08:00:00.000] [crossdesk] [info] Logger initialized"
private let displays = [
    crossdesk("08:00:00.100", "macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'"),
    crossdesk("08:00:00.100", "macOS display discovered: index=1, display_id=367, name='Snug 手机屏'"),
]
/// 09:03 连入、09:10 断开，断言 9.5 秒后才放
private let session = [
    crossdesk("09:03:53.951", "Requested display and system idle-sleep inhibition for screen sharing"),
    crossdesk("09:10:08.951", "Last remote controller disconnected; recovering privacy, reason=connection_closed"),
    crossdesk("09:10:18.451", "Released screen sharing power inhibitors"),
]
private let snugDetected = "[2026-11-23 09:03:54.400] [info] 检测到 CrossDesk 连入（共享断言=有（进程 78275） 距上次在场 0.00s）"

private func facts(version: String? = CrossDeskRemote.verifiedVersion, processes: [Int32] = [78275],
                   found: Set<String> = Set([CrossDeskRemote.sharingAssertion] + CrossDeskLogLine.phrases), sharingNow: [Int32]? = [],
                   log: [String]? = [started] + displays + session, snug: [String] = [snugDetected],
                   online: Set<DisplayID> = [367]) -> CrossDeskCheck.Facts {
    CrossDeskCheck.Facts(hours: 4, since: at("07:00:00.000"), version: version, processes: processes, foundInProgram: found,
                         sharingNow: sharingNow, log: log, timeZone: zone, snugLog: snug, onlineSnugDisplays: online)
}

private func item(_ title: String, in items: [RemoteCheck.Item]) -> RemoteCheck.Item? { items.first { $0.title == title } }

@Suite("CrossDesk 兼容自检")
struct CrossDeskCheckTests {
    @Test("一切照旧：逐项通过，报出断开到放断言的延迟，结论无问题、退出码 0")
    func healthy() throws {
        let items = CrossDeskCheck.evaluate(facts())
        #expect(items.map(\.title) == ["CrossDesk", "进程", "会话信号", "日志写法", "远程记录", "认屏"])
        #expect(items.allSatisfy { $0.status == .ok })
        #expect(try #require(item("远程记录", in: items)).detail.contains("最长 9.5 秒"))
        #expect(RemoteCheck.report(items, remote: CrossDeskRemote.identity, hours: 4, at: at("10:00:00.000")).contains("结论：未发现兼容问题"))
        #expect(RemoteCheck.exitCode(items) == 0)
    }

    @Test("没装：只报这一项，不通过")
    func notInstalled() {
        let items = CrossDeskCheck.evaluate(facts(version: nil))
        #expect(items.count == 1)
        #expect(items.first?.status == .fail)
    }

    @Test("程序里没了断言名、或查不了断言：会话信号不通过，退出码 1（判在场全靠它）")
    func sharingSignalBroken() {
        let renamed = CrossDeskCheck.evaluate(facts(found: Set(CrossDeskLogLine.phrases)))
        #expect(item("会话信号", in: renamed)?.status == .fail)
        #expect(RemoteCheck.exitCode(renamed) == 1)
        #expect(item("会话信号", in: CrossDeskCheck.evaluate(facts(sharingNow: nil)))?.status == .fail)
        #expect(item("会话信号", in: CrossDeskCheck.evaluate(facts(sharingNow: [78275])))?.detail.contains("此刻有人远程（进程 78275）") == true)
    }

    @Test("日志里认的句子程序里少了一句：只需留意，点名是哪句")
    func phraseMissing() throws {
        let check = try #require(item("日志写法", in: CrossDeskCheck.evaluate(facts(found: [CrossDeskRemote.sharingAssertion, CrossDeskLogLine.started]))))
        #expect(check.status == .warn)
        #expect(check.detail.contains(CrossDeskLogLine.displayFound))
        #expect(!check.detail.contains("「\(CrossDeskLogLine.started)」"))
    }

    @Test("断开到放断言的延迟只配同一个实例里的一对：上一个实例断开后被杀（没放断言），不和下一个实例的放断言配成一对")
    func releaseDelayWithinInstance() throws {
        let killed = [started, session[0], session[1],
                      "[2026-11-23 09:30:00.000] [crossdesk] [info] Logger initialized",
                      crossdesk("09:31:00.000", "Requested display and system idle-sleep inhibition for screen sharing"),
                      crossdesk("09:32:00.000", "Released screen sharing power inhibitors")]
        let snug = [snugDetected, "[2026-11-23 09:31:00.400] [info] 检测到 CrossDesk 连入（共享断言=有（进程 9） 距上次在场 0.00s）"]
        let check = try #require(item("远程记录", in: CrossDeskCheck.evaluate(facts(log: killed, snug: snug))))
        #expect(check.status == .ok)
        #expect(!check.detail.contains("断开到放断言"))
    }

    @Test("CrossDesk 开始共享了、Snug 没记到连入：需留意，列出时刻；差 15 秒以内算对上")
    func missedSession() throws {
        let missed = try #require(item("远程记录", in: CrossDeskCheck.evaluate(facts(snug: []))))
        #expect(missed.status == .warn)
        #expect(missed.detail.contains("Snug 认出 0 次") && missed.detail.contains("09:03"))
        let late = "[2026-11-23 09:04:08.900] [info] 检测到 CrossDesk 连入（共享断言=有（进程 78275） 距上次在场 0.00s）"
        #expect(item("远程记录", in: CrossDeskCheck.evaluate(facts(snug: [late])))?.status == .ok)
        let tooLate = "[2026-11-23 09:04:09.000] [info] 检测到 CrossDesk 连入（共享断言=有（进程 78275） 距上次在场 0.00s）"
        #expect(item("远程记录", in: CrossDeskCheck.evaluate(facts(snug: [tooLate])))?.status == .warn)
        // 别家的连入不算
        let uu = "[2026-11-23 09:03:54.400] [info] 检测到 UU 连入（overlay=否 控制端=读不到 capture=是 距上次在场 0.00s）"
        #expect(item("远程记录", in: CrossDeskCheck.evaluate(facts(snug: [uu])))?.status == .warn)
    }

    @Test("没有远程、Snug 记到连入日志里却没有、日志读不到：各自需留意；读不到时不报认屏")
    func nothingToMatch() throws {
        let quiet = try #require(item("远程记录", in: CrossDeskCheck.evaluate(facts(log: [started] + displays, snug: []))))
        #expect(quiet.status == .warn && quiet.detail.contains("没有远程"))
        let rewritten = try #require(item("远程记录", in: CrossDeskCheck.evaluate(facts(log: [started] + displays))))
        #expect(rewritten.status == .warn && rewritten.detail.contains("写法可能改了"))
        let unreadable = CrossDeskCheck.evaluate(facts(log: nil))
        #expect(item("远程记录", in: unreadable)?.status == .warn)
        #expect(item("认屏", in: unreadable) == nil)
        // 回看起点之前的共享不算
        let old = [crossdesk("06:59:59.000", "Requested display and system idle-sleep inhibition for screen sharing")]
        #expect(item("远程记录", in: CrossDeskCheck.evaluate(facts(log: old, snug: [])))?.detail.contains("没有远程") == true)
    }

    @Test("认屏：此刻在线的 Snug 屏不在 CrossDesk 启动时认到的里面要重启；只认最近一次启动；启动的日志滚动掉了、没记下屏各自说明")
    func displaySeen() throws {
        let unseen = try #require(item("认屏", in: CrossDeskCheck.evaluate(facts(online: [367, 368]))))
        #expect(unseen.status == .warn && unseen.detail.contains("#368") && unseen.detail.contains("重启 CrossDesk"))
        let restarted = [started] + displays + session + ["[2026-11-23 09:20:00.000] [crossdesk] [info] Logger initialized", displays[0]]
        #expect(item("认屏", in: CrossDeskCheck.evaluate(facts(log: restarted)))?.status == .warn)
        #expect(item("认屏", in: CrossDeskCheck.evaluate(facts(online: [])))?.status == .info)
        #expect(item("认屏", in: CrossDeskCheck.evaluate(facts(log: displays + session)))?.status == .info)
        #expect(item("认屏", in: CrossDeskCheck.evaluate(facts(log: [started] + session)))?.status == .warn)
    }

    @Test("取证材料只放回看起点之后的原文，续行跟着上一行走")
    func recent() {
        let lines = [crossdesk("06:59:00.000", "old"), "  continuation of old", crossdesk("07:00:00.000", "new"), "  continuation of new"]
        #expect(CrossDeskCheck.recent(lines, since: at("07:00:00.000"), in: zone) == Array(lines[2...]))
    }
}
