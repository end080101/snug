import Foundation
import Testing
@testable import RemoteUU
@testable import SnugCore

/// 用和日志同样格式的字符串写断言里的时刻，一眼能对上夹具（夹具 2224 是 11-23 的，1901、2000 是 11-12 的）
private func ts(_ s: String, day: String = "2026-11-12") -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
    return f.date(from: "\(day) \(s)-0800")!
}

/// 按时间顺序回放夹具，在每个探测时刻问一次推流表（只用该时刻之前的日志）
private func replay<T>(_ name: String, at probes: [String], day: String = "2026-11-12",
                       _ ask: (CaptureStreams, Date) -> T) throws -> [String: T] {
    let parser = CaptureLogParser()
    var streams = CaptureStreams()
    var result: [String: T] = [:]
    var pending = probes
    for line in try UUFixtures.lines(name) {
        guard let record = parser.parse(line: line) else { continue }
        while let p = pending.first, ts(p, day: day) < record.date {
            result[p] = ask(streams, ts(p, day: day))
            pending.removeFirst()
        }
        streams.apply(record)
    }
    for p in pending { result[p] = ask(streams, ts(p, day: day)) }
    return result
}

private func activity(_ name: String, at probes: [String], day: String = "2026-11-12") throws -> [String: Bool] {
    try replay(name, at: probes, day: day) { $0.isActive(at: $1) }
}

private func displays(_ name: String, at probes: [String], day: String = "2026-11-12") throws -> [String: DisplayID?] {
    try replay(name, at: probes, day: day) { $0.streamingDisplay(at: $1) }
}

private func message(_ text: String, process: String = "/Applications/UURemote.app/Contents/Helpers/UURemoteServer",
                     at time: String = "19:01:43.417100", processID: Int? = nil) -> String {
    var obj: [String: Any] = ["timestamp": "2026-11-12 \(time)-0800", "processImagePath": process, "eventMessage": text]
    obj["processID"] = processID
    return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
}

private func scDisplay(_ id: Int) -> String {
    " [INFO] -[SCDisplay initWithDict:]:196 (0x1) displayID=\(id) frame=(0.000000,0.000000,1320.000000,2868.000000) width=1320 height=2868"
}

private func startCapture(_ stream: UInt64 = 1) -> String {
    " [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 0x\(String(stream, radix: 16)) streamID=<private>"
}

private func stopCapture(_ stream: UInt64 = 1) -> String {
    " [INFO] -[SCStream stopCaptureWithCompletionHandler:]:983 0x\(String(stream, radix: 16)) streamID=<private>"
}

private func released(_ stream: UInt64) -> String {
    " [INFO] -[SCStream dealloc]:697 0x\(String(stream, radix: 16)) streamID=<private>"
}

private func addOutput(_ stream: UInt64, type: Int) -> String {
    " [INFO] -[SCStream addStreamOutput:type:sampleHandlerQueue:error:]:824 0x\(String(stream, radix: 16)) streamID=<private> "
        + "output=0x7ce6cbcaa0 type=\(type) sampleHandlerQueue=0x7ce7ae5080"
}

private extension CaptureStreams {
    /// 从 start 起按秒数偏移依次喂进去
    mutating func feed(_ start: Date, _ script: [(TimeInterval, CaptureLogEvent)]) {
        for (t, event) in script { apply(CaptureLogRecord(date: start + t, event: event)) }
    }
}

@Suite("推流日志 CaptureLogParser / CaptureStreams")
struct CaptureLogTests {
    @Test("逐类识别 UURemoteServer 的行：开推、停、释放、登记声音输出都带流的地址")
    func classify() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(startCapture(0x7ce642ab80)))?.event == .captureStarted(stream: 0x7ce642ab80))
        #expect(p.parse(line: message(stopCapture(0x7ce642ab80)))?.event == .captureStopped(stream: 0x7ce642ab80))
        #expect(p.parse(line: message(addOutput(0x7ce6429080, type: 1)))?.event == .soundAdded(stream: 0x7ce6429080))
        #expect(p.parse(line: message(addOutput(0x7ce6429080, type: 2)))?.event == .soundAdded(stream: 0x7ce6429080))
        #expect(p.parse(line: message(addOutput(0x7ce642ab80, type: 0))) == nil)   // 画面输出，每路都有
        #expect(p.parse(line: message(released(0x7ce642ab80)))?.event == .released(stream: 0x7ce642ab80))
    }

    @Test("不相干的行一律忽略：不带地址的开推和停、停流回调的报错、登记输出的收尾、编码会话、别的进程、非 JSON、log 的结尾统计")
    func ignores() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(" [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 streamID=<private>")) == nil)
        #expect(p.parse(line: message(" [INFO] _SCStream_UpdateAndHandleFrameStatus:1729 Stopping stream due to stream frameStatus=7")) == nil)
        #expect(p.parse(line: message(" [ERROR] -[SCStream stopCaptureWithCompletionHandler:]_block_invoke_2:995 error=Error Domain=x Code=-3808")) == nil)
        #expect(p.parse(line: message(" [INFO] -[SCStream addStreamOutput:type:sampleHandlerQueue:error:]:828")) == nil)
        #expect(p.parse(line: message("<<<< VT-CS >>>> VTCompressionSessionInvalidate: [0x1:CS/ZDF] invalidating compression session: encoded 750 dropped 0 duration 19581 [ms]")) == nil)
        #expect(p.parse(line: message(startCapture(), process: "/usr/libexec/other")) == nil)
        #expect(p.parse(line: "Filtering the log data using \"process == UURemoteServer\"") == nil)
        #expect(p.parse(line: #"{"count":28,"finished":1}"#) == nil)
        #expect(p.parse(line: message("CGSDisplayNotifyProc: got notification kCGSDisplayWillReconfigure")) == nil)
    }

    @Test("时间戳按日志自带的时区解析")
    func timestamp() {
        #expect(CaptureLogParser().parse(line: message(startCapture()))?.date == ts("19:01:43.417"))
    }

    @Test("19:01 夹具：推流从 02.387 开始，关物理屏时两路停了又马上重开不算结束，43.414 停后 3 秒判停")
    func replay1901() throws {
        #expect(CaptureStreams.restartGrace == 3)
        let a = try activity("1901", at: ["19:01:02.300", "19:01:02.500", "19:01:23.500", "19:01:27.000",
                                         "19:01:43.000", "19:01:46.400", "19:01:46.500"])
        #expect(a["19:01:02.300"] == false)
        #expect(a["19:01:02.500"] == true)
        #expect(a["19:01:23.500"] == true)   // 23.405 两路都停，23.561 重新开推，中间在宽限里
        #expect(a["19:01:27.000"] == true)   // 23.561 开推的那路一直开着
        #expect(a["19:01:43.000"] == true)
        #expect(a["19:01:46.400"] == true)   // 43.414 + 3 = 46.414
        #expect(a["19:01:46.500"] == false)
    }

    @Test("20:00 夹具：两段会话中间的空档判停，第二段重新开始；第二段的流用回了第一段用过的地址")
    func replay2000() throws {
        let a = try activity("2000", at: ["20:00:42.000", "20:01:00.000", "20:01:06.700", "20:01:06.800", "20:01:15.000",
                                         "20:01:21.500", "20:01:40.000", "20:01:59.100", "20:01:59.300"])
        #expect(a["20:00:42.000"] == true)
        #expect(a["20:01:00.000"] == true)
        #expect(a["20:01:06.700"] == true)    // 03.772 + 3 = 06.772
        #expect(a["20:01:06.800"] == false)
        #expect(a["20:01:15.000"] == false)
        #expect(a["20:01:21.500"] == true)
        #expect(a["20:01:40.000"] == true)    // 23.446 开推的流用的是 41.704 那路的地址
        #expect(a["20:01:59.100"] == true)    // 56.203 + 3 = 59.203
        #expect(a["20:01:59.300"] == false)
    }

    @Test("22:24、22:26 夹具（11-23 本机）：画面开在主屏 1、声音流也挂在 1；切到手机屏是先停旧画面、30 毫秒后开新的，一直算在推、认出新屏；两路一起停，3 秒后判停")
    func replay2224() throws {
        let day = "2026-11-23"
        let probes = ["22:24:10.000", "22:24:19.680", "22:24:30.000", "22:24:52.300", "22:24:52.400",
                      "22:26:50.000", "22:26:54.980", "22:27:30.000", "22:28:24.100", "22:28:24.200"]
        let a = try activity("2224", at: probes, day: day)
        let d = try displays("2224", at: probes, day: day)
        #expect(d["22:24:10.000"] == .some(1))
        #expect(a["22:24:19.680"] == true)     // 19.664 停旧画面，19.695 才为 32 开推：声音流还开着，旧画面在宽限里
        #expect(d["22:24:19.680"] == .some(1))
        #expect(d["22:24:30.000"] == .some(32))
        #expect(a["22:24:52.300"] == true)     // 49.352 + 3 = 52.352
        #expect(a["22:24:52.400"] == false)
        #expect(d["22:24:52.400"] == .some(nil))
        #expect(d["22:26:50.000"] == .some(1))
        #expect(d["22:26:54.980"] == .some(1))   // 54.963 停旧画面，55.000 为 33 开推
        #expect(d["22:27:30.000"] == .some(33))
        #expect(a["22:28:24.100"] == true)     // 21.179 + 3 = 24.179
        #expect(a["22:28:24.200"] == false)
    }

    @Test("声音流不盖掉画面：画面开在手机屏 79，紧跟着为主屏 1 起的声音流不算（形态取自 11-12 22:57 那次远程）")
    func soundStreamKeepsDisplay() {
        let lines = [
            ("22:57:12.968000", scDisplay(79)), ("22:57:12.969000", addOutput(0x1, type: 0)), ("22:57:12.969100", startCapture(0x1)),
            ("22:57:13.023000", scDisplay(1)), ("22:57:13.023100", addOutput(0x2, type: 1)), ("22:57:13.023200", addOutput(0x2, type: 0)),
            ("22:57:13.023300", startCapture(0x2)),
        ]
        let p = CaptureLogParser()
        var s = CaptureStreams()
        for (time, text) in lines { if let r = p.parse(line: message(text, at: time)) { s.apply(r) } }
        #expect(s.streamingDisplay(at: ts("22:57:14.000")) == 79)
    }

    @Test("先开新画面、过几秒才停旧的（#56）：开推那一刻就认出新屏，旧的停了也一直算在推")
    func newPictureBeforeOldStops() {
        // 时刻取自 #56：19:06:51 画面开在外接屏 3，57.382 为电脑屏 152 开推，19:07:02.516 才停旧的
        let start = ts("19:06:51.000")
        var s = CaptureStreams()
        s.feed(start, [(0, .displayDescribed(3)), (0.1, .captureStarted(stream: 1)),
                       (0.3, .displayDescribed(1)), (0.3, .soundAdded(stream: 2)), (0.4, .captureStarted(stream: 2)),
                       (6.3, .displayDescribed(152)), (6.382, .captureStarted(stream: 3))])
        #expect(s.streamingDisplay(at: start + 7) == 152)
        s.feed(start, [(11.516, .captureStopped(stream: 1))])
        #expect(s.isActive(at: start + 15.8))
        #expect(s.streamingDisplay(at: start + 15.8) == 152)
        s.feed(start, [(20, .captureStopped(stream: 2)), (20.002, .captureStopped(stream: 3))])
        #expect(s.isActive(at: start + 22.9))
        #expect(!s.isActive(at: start + 23.1))
    }

    @Test("停的那句没记到时，释放那句照样让这路流收尾")
    func releaseEndsStream() {
        let start = ts("21:00:00.000")
        var s = CaptureStreams()
        s.feed(start, [(0, .displayDescribed(32)), (0.1, .captureStarted(stream: 1)), (10, .released(stream: 1))])
        #expect(s.isActive(at: start + 12.9))
        #expect(!s.isActive(at: start + 13.1))
    }

    @Test("SCDisplay initWithDict 的 displayID 解析成「描述了哪块屏」")
    func describesDisplay() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(scDisplay(14)))?.event == .displayDescribed(14))
        #expect(p.parse(line: message(" [INFO] -[SCDisplay initWithDict:]:196 (0x1) frame=(0,0,1,1)")) == nil)
    }

    @Test("推的屏是开推前最后描述的那块；中途枚举别的屏不改；停了过了宽限就清空")
    func streamingDisplay() {
        // 形态取自 2026-11-12 20:00:41–44 与 20:01:03 的真实日志：先枚举 1、14，再为 1 建过滤器并开推；
        // 关屏后停流，枚举 14、为 14 建过滤器并开推；20:01:03.772 停流
        let lines = [
            ("20:00:41.830000", scDisplay(1)), ("20:00:41.830100", scDisplay(14)), ("20:00:41.831000", scDisplay(1)),
            ("20:00:41.831500", startCapture(0x1)),
            ("20:00:43.940000", stopCapture(0x1)),
            ("20:00:44.046000", scDisplay(14)), ("20:00:44.075000", scDisplay(14)),
            ("20:00:44.075500", startCapture(0x2)),
            ("20:00:50.000000", scDisplay(1)),
            ("20:01:03.772000", stopCapture(0x2)),
        ]
        let p = CaptureLogParser()
        var s = CaptureStreams()
        var seen: [String: DisplayID?] = [:]
        func probe(_ t: String) { seen[t] = s.streamingDisplay(at: ts(t)) }
        probe("20:00:41.000")
        for (time, text) in lines {
            if time == "20:00:43.940000" { probe("20:00:43.000") }
            if time == "20:00:50.000000" { probe("20:00:49.000") }
            guard let r = p.parse(line: message(text, at: time)) else { continue }
            s.apply(r)
        }
        probe("20:01:00.000")
        probe("20:01:06.700")
        probe("20:01:06.800")
        #expect(seen["20:00:41.000"] == .some(nil))
        #expect(seen["20:00:43.000"] == .some(1))
        #expect(seen["20:00:49.000"] == .some(14))
        #expect(seen["20:01:00.000"] == .some(14))   // 50.000 枚举了 1，不算换屏
        #expect(seen["20:01:06.700"] == .some(14))   // 03.772 + 3 = 06.772 之前仍在宽限里
        #expect(seen["20:01:06.800"] == .some(nil))
    }

    @Test("换手接管（V12）：前一台的两路停掉 0.6～0.7 秒后新的一台起推流，一直算推流中；新的一台推的是它开推前描述的屏（主屏）")
    func takeoverKeepsStreaming() {
        let start = ts("21:00:00.000")
        var s = CaptureStreams()
        s.feed(start, [(0, .displayDescribed(79)), (0.1, .captureStarted(stream: 1)),
                       (0.2, .displayDescribed(1)), (0.3, .soundAdded(stream: 2)), (0.3, .captureStarted(stream: 2)),
                       (30, .captureStopped(stream: 1)), (30.002, .captureStopped(stream: 2))])
        #expect(s.isActive(at: start + 30.4))
        s.feed(start, [(30.69, .displayDescribed(1)), (30.7, .captureStarted(stream: 3))])
        #expect(s.isActive(at: start + 40))
        #expect(s.streamingDisplay(at: start + 40) == 1)
    }

    @Test("监听中途启动：回放启动前的日志再接上实时日志，认得出正在推、推的是哪块屏")
    func resumedFromHistory() {
        let d = ts("22:00:00.000")
        let history = [
            CaptureLogRecord(date: d, event: .displayDescribed(79), processID: 100),
            CaptureLogRecord(date: d + 0.1, event: .captureStarted(stream: 1), processID: 100),
            CaptureLogRecord(date: d + 600, event: .captureStopped(stream: 1), processID: 100),
        ]
        // 实时这段和回放的最后一条重叠，之后又开推
        let live = [
            CaptureLogRecord(date: d + 600, event: .captureStopped(stream: 1)),
            CaptureLogRecord(date: d + 600.5, event: .displayDescribed(5)),
            CaptureLogRecord(date: d + 600.6, event: .captureStarted(stream: 2)),
        ]
        let s = CaptureStreams.resumed(history: history, live: live, server: 100)
        #expect(s.isActive(at: d + 700))
        #expect(s.streamingDisplay(at: d + 700) == 5)
        // 没有回放时（回看失败）只靠实时日志
        #expect(CaptureStreams.resumed(history: [], live: Array(live.prefix(1)), server: 100).isActive(at: d + 700) == false)
    }

    @Test("回放只认此刻的 UURemoteServer 进程：上一个进程崩溃前开的推流不算；服务端没在运行、读不到进程号的都不认")
    func resumedIgnoresOtherProcesses() {
        let d = ts("22:00:00.000")
        // 进程 100 开推后崩溃，没留下停流的日志；现在的服务端是 200
        let crashed = [
            CaptureLogRecord(date: d, event: .displayDescribed(79), processID: 100),
            CaptureLogRecord(date: d + 0.1, event: .captureStarted(stream: 1), processID: 100),
        ]
        let later = d + 600
        #expect(!CaptureStreams.resumed(history: crashed, live: [], server: 200).isActive(at: later))
        #expect(!CaptureStreams.resumed(history: crashed, live: [], server: nil).isActive(at: later))
        #expect(CaptureStreams.resumed(history: crashed, live: [], server: 100).isActive(at: later))
        let unknown = crashed.map { CaptureLogRecord(date: $0.date, event: $0.event) }
        #expect(!CaptureStreams.resumed(history: unknown, live: [], server: 100).isActive(at: later))
        // 当前进程自己开的推流照样认
        let current = crashed + [CaptureLogRecord(date: d + 300, event: .captureStarted(stream: 2), processID: 200)]
        #expect(CaptureStreams.resumed(history: current, live: [], server: 200).isActive(at: later))
    }

    @Test("解析时带上打日志的进程号，没有就是 nil")
    func parsesProcessID() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(startCapture(), processID: 18369))?.processID == 18369)
        #expect(p.parse(line: message(startCapture()))?.processID == nil)
    }

    @Test("按字节切行：一行切在两块里、一块里有多行、结尾半行等到 finish 才解析")
    func lineBuffer() {
        let a = message(startCapture(), at: "19:01:43.000000"), b = message(stopCapture(), at: "19:01:44.000000")
        let bytes = Array((a + "\n" + b).utf8)
        var buffer = CaptureLogLineBuffer()
        let cut = a.utf8.count / 2
        #expect(buffer.feed(Data(bytes[..<cut])).isEmpty)
        #expect(buffer.feed(Data(bytes[cut...])).map(\.event) == [.captureStarted(stream: 1)])
        #expect(buffer.finish().map(\.event) == [.captureStopped(stream: 1)])
        var many = CaptureLogLineBuffer()
        #expect(many.feed(Data((a + "\n" + b + "\n").utf8)).map(\.event) == [.captureStarted(stream: 1), .captureStopped(stream: 1)])
    }

    @Test("日志过滤条件：解析器认得的每类行都含其中一个关键词（过滤了不会漏）")
    func predicateCoversClassified() {
        for text in [scDisplay(1), startCapture(), stopCapture(), addOutput(2, type: 1), released(1)] {
            #expect(CaptureLogParser.classify(text) != nil)
            #expect(CaptureLogParser.keywords.contains { text.contains($0) })
        }
        #expect(CaptureLogParser.predicate.hasPrefix("process == \"UURemoteServer\" AND ("))
    }
}
