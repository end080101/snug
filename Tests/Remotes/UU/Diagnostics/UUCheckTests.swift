import Foundation
import Testing
@testable import RemoteUU
@testable import SnugCore

/// 夹具里没留进程号，按此刻的 UURemoteServer 补上
private let serverPID: pid_t = 4242

/// 推流事件取自 CaptureLogTests 的夹具 2257：远程开头先为手机屏 79 开推，紧跟着为主屏 1 再起一路
private func records(_ name: String) throws -> [CaptureLogRecord] {
    let parser = CaptureLogParser()
    return try UUFixtures.lines(name).compactMap { parser.parse(line: $0) }
        .map { CaptureLogRecord(date: $0.date, event: $0.event, processID: serverPID) }
}

/// 夹具 2257 的第一次推流开始：2026-11-12 22:57:12.969 -0800
private let remoteStart = Date(timeIntervalSince1970: 1_794_553_032.969)

private func logLine(_ date: Date, _ message: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return "[\(f.string(from: date))] [info] \(message)"
}

/// 每次连入一行信号、每次远程一行开始，控制端和屏编号各一行。会话和连入的行用正式的 logLine 生成，跟着产出方的写法走
private func snugLog(sessions: [Date] = [remoteStart], displays: [DisplayID] = [79], controller: String? = "iPhone",
                     captures: [Bool?]? = nil) -> [String] {
    let signals = (captures ?? sessions.map { _ in true }).map { capture in
        let evidence = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: capture).description
        return logLine(remoteStart, ConnectionTracker.logLine(.connected(controllers: []), remote: UURemote.identity.logName,
                                                              evidence: evidence, sincePresent: 0, quietLeft: nil))
    }
    return signals + sessions.map { logLine($0, SessionTransition.began(controllers: []).logLine) }
        + (controller.map { [logLine(remoteStart, SessionTransition.controllersChanged([$0]).logLine)] } ?? [])
        + displays.map { logLine(remoteStart, "「Snug 手机屏」#\($0) 已建好（540 宽）") }
}

private func facts(version: String? = UUCheck.verifiedVersion, server: UUCheck.Server? = UUCheck.Server(pid: serverPID, start: nil), servers: [String] = ["Contents/Helpers/UURemoteServer"],
                   linkers: [String: [String]] = [UUCheck.captureFramework: ["Contents/Frameworks/libstreamer.dylib"],
                                                  UUCheck.encoderFramework: ["Contents/Frameworks/libstreamer.dylib"]],
                   capture: [CaptureLogRecord]?, snug: [String] = snugLog(), online: Set<DisplayID> = [],
                   now: ControllerTable? = .unrecognized) -> UUCheck.Facts {
    UUCheck.Facts(hours: 4, since: remoteStart - 4 * 3600, version: version, appRunning: true, server: server, serverExecutables: servers,
                  linkers: linkers, capture: capture, snugLog: snug, onlineSnugDisplays: online, controllersNow: now)
}

private func item(_ title: String, in items: [UUCheck.Item]) -> UUCheck.Item? { items.first { $0.title == title } }

@Suite("UU远程 兼容自检 UUCheck")
struct UUCheckTests {
    @Test("一切照旧：没有问题，切到 Snug 的屏认得出（取的是第一路的屏，第二路的主屏不盖掉它）")
    func healthy() throws {
        let items = UUCheck.evaluate(facts(capture: try records("2257")))
        #expect(!items.contains { $0.status == .fail || $0.status == .warn })
        #expect(item("推流日志", in: items)?.detail.contains("推流开始 2 次") == true)
        #expect(item("推流屏", in: items)?.status == .ok)
        #expect(item("推流屏", in: items)?.detail.contains("Snug 的屏 #79") == true)
        #expect(RemoteCheck.report(items, title: UUCheck.title, hours: 4, at: remoteStart).contains("结论：未发现兼容问题"))
    }

    @Test("没装 UU：只报这一项")
    func notInstalled() {
        let items = UUCheck.evaluate(facts(version: nil, capture: []))
        #expect(items.map(\.status) == [.fail])
    }

    @Test("版本和上次核对的不同：报告里写出对照")
    func newerVersion() throws {
        let items = UUCheck.evaluate(facts(version: "9.9.9", capture: try records("2257")))
        #expect(items.first?.detail == "版本 9.9.9（上次核对的是 \(UUCheck.verifiedVersion)）；核对范围：最近 4 小时")
    }

    @Test("后台进程改了名、不再链接抓屏框架：都是问题；只少了编码框架：需留意")
    func binaries() throws {
        let capture = try records("2257")
        #expect(item("后台进程", in: UUCheck.evaluate(facts(servers: [], capture: capture)))?.status == .fail)
        #expect(item("推流框架", in: UUCheck.evaluate(facts(linkers: [:], capture: capture)))?.status == .fail)
        let noEncoder = [UUCheck.captureFramework: ["Contents/Frameworks/libstreamer.dylib"]]
        #expect(item("推流框架", in: UUCheck.evaluate(facts(linkers: noEncoder, capture: capture)))?.status == .warn)
    }

    @Test("Snug 记到了远程，UU 日志里却没有可认的推流开始：日志写法变了")
    func captureMissing() {
        let items = UUCheck.evaluate(facts(capture: []))
        #expect(item("推流日志", in: items)?.status == .fail)
        #expect(item("推流屏", in: items) == nil)
        #expect(RemoteCheck.report(items, title: UUCheck.title, hours: 4, at: remoteStart).contains("结论：发现 1 项问题"))
    }

    @Test("这段时间没有远程：无从核对，提示先连一次")
    func nothingToCheck() {
        let items = UUCheck.evaluate(facts(capture: [], snug: snugLog(sessions: [], displays: [], controller: nil)))
        #expect(item("推流日志", in: items)?.status == .warn)
        #expect(item("连接检测", in: items) == nil)
        #expect(item("控制端", in: items) == nil)
    }

    @Test("系统日志读不出来：需留意，不当成 UU 的问题")
    func logUnreadable() {
        #expect(item("推流日志", in: UUCheck.evaluate(facts(capture: nil)))?.status == .warn)
    }

    @Test("Snug 记到的远程对不上推流开始：需留意")
    func unmatchedSession() throws {
        let items = UUCheck.evaluate(facts(capture: try records("2257"), snug: snugLog(sessions: [remoteStart, remoteStart + 3600])))
        #expect(item("推流日志", in: items)?.status == .warn)
        #expect(item("推流日志", in: items)?.detail.contains("2 次远程里 1 次对得上") == true)
    }

    @Test("推流开始前没有屏描述：认不出在推哪块屏；只推过别的屏：待下次核对")
    func streamedDisplay() throws {
        let starts = try records("2257").filter { $0.event == .captureStarted }
        #expect(item("推流屏", in: UUCheck.evaluate(facts(capture: starts)))?.status == .fail)
        #expect(item("推流屏", in: UUCheck.evaluate(facts(capture: try records("2257"), snug: snugLog(displays: []))))?.status == .info)
    }

    @Test("设为主屏的那块常驻、建屏的日志早在回看之前：此刻在线的 Snug 屏也算")
    func residentMain() throws {
        let items = UUCheck.evaluate(facts(capture: try records("2257"), snug: snugLog(displays: []), online: [79]))
        #expect(item("推流屏", in: items)?.status == .ok)
    }

    @Test("只认此刻的 UURemoteServer 进程：更新前旧进程的推流和远程不替新版本作证")
    func currentProcessOnly() {
        let restart = remoteStart + 3600
        let capture = [
            CaptureLogRecord(date: remoteStart, event: .displayDescribed(79), processID: 100),
            CaptureLogRecord(date: remoteStart, event: .captureStarted, processID: 100),
            CaptureLogRecord(date: restart + 60, event: .captureStarted, processID: 200),
        ]
        let server = UUCheck.Server(pid: 200, start: restart)
        let items = UUCheck.evaluate(facts(server: server, capture: capture, snug: snugLog(sessions: [remoteStart, restart + 60])))
        #expect(items.first?.detail.hasSuffix("核对范围：UURemoteServer \(UUCheck.clock(restart)) 启动以来") == true)
        #expect(item("推流日志", in: items)?.detail == "推流开始 1 次、停止 0 次；Snug 记到的 1 次远程都对得上")
        // 新进程开推前没有屏描述：旧进程描述过的 79 不能带过来
        #expect(item("推流屏", in: items)?.status == .fail)
        // 新进程启动以来还没远程过：无从核对，不拿旧进程的记录凑
        let idle = UUCheck.evaluate(facts(server: UUCheck.Server(pid: 300, start: restart + 7200), capture: capture))
        #expect(item("推流日志", in: idle)?.status == .warn)
        #expect(item("推流日志", in: idle)?.detail.hasPrefix("UURemoteServer") == true)
    }

    @Test("连接检测：推流信号未知的连入不计；一次都没亮是问题，亮了一部分需留意")
    func detection() throws {
        let capture = try records("2257")
        func status(_ values: [Bool?]) -> UUCheck.Status? {
            item("连接检测", in: UUCheck.evaluate(facts(capture: capture, snug: snugLog(captures: values))))?.status
        }
        #expect(status([true, nil]) == .ok)
        #expect(status([nil]) == nil)
        #expect(status([false, nil]) == .fail)
        #expect(status([true, false]) == .warn)
    }

    @Test("连接检测：远程过、日志里却认不出连入（Snug 改了日志写法），或信号快照读不出，需留意，不悄悄略过")
    func detectionUnreadable() throws {
        let capture = try records("2257")
        let noDetections = snugLog(captures: [])
        #expect(item("连接检测", in: UUCheck.evaluate(facts(capture: capture, snug: noDetections)))?.status == .warn)
        let garbled = snugLog(captures: []) + [logLine(remoteStart, "检测到 UU 连入（信号=改了写法 距上次在场 0.00s）")]
        #expect(item("连接检测", in: UUCheck.evaluate(facts(capture: capture, snug: garbled)))?.status == .warn)
    }

    @Test("别家远控的远程不算 UU 的：连入、会话、控制端都归那一家，UU 的连接检测、控制端两项不出")
    func otherRemoteNotCounted() throws {
        let other = [
            logLine(remoteStart, ConnectionTracker.logLine(.connected(controllers: []), remote: "甲", evidence: "信号=一", sincePresent: 0, quietLeft: nil)),
            logLine(remoteStart, SessionTransition.began(controllers: ["甲的设备"]).logLine),
        ]
        let items = UUCheck.evaluate(facts(capture: try records("2257"), snug: other))
        #expect(item("连接检测", in: items) == nil)
        #expect(item("控制端", in: items) == nil)
        #expect(item("推流日志", in: items)?.status == .ok)
    }

    @Test("控制端：远程过却一次都没认出需留意；此刻表上有名字也算认出")
    func controllers() throws {
        let capture = try records("2257")
        #expect(item("控制端", in: UUCheck.evaluate(facts(capture: capture, snug: snugLog(controller: nil))))?.status == .warn)
        let live = UUCheck.evaluate(facts(capture: capture, snug: snugLog(controller: nil), now: .shown(["iPhone"])))
        #expect(item("控制端", in: live)?.status == .ok)
        #expect(item("控制端", in: live)?.detail == "此刻：iPhone")
    }

    @Test("旧的诊断参数 --dump-uu、--check-uu 不留别名（改为 --dump-remote uu、--check-remote uu）")
    func oldFlagsGone() {
        #expect(throws: LaunchModeError.unknownFlag("--dump-uu")) { try LaunchMode.parse(["--dump-uu"]) }
        #expect(throws: LaunchModeError.unknownFlag("--check-uu")) { try LaunchMode.parse(["--check-uu"]) }
    }
}
