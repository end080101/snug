// UU 此刻开着的抓屏流，记成一张表（纯值类型，时间由调用方给）。
// UURemoteServer 用 ScreenCaptureKit 抓屏，每路流是一个 SCStream 对象，日志里带着它的地址：登记输出 → 开推 → 停 → 释放，前后对得上。
// 表按地址记每路流推哪块屏、带不带声音、何时开推、何时停；「在不在推」「推哪块屏」都从表里查，不按事件的先后去猜：
// - UU 一次远程开头起两路流：一路是画面；紧跟着一路登记了声音输出，挂在主屏上，一直推到远程结束。
//   声音流不是用户在看的屏（2026-11-23 22:24、22:26 两次远程，夹具 2224）
// - 切屏时新旧两路谁先谁后不一定：本机是先停旧画面、30 毫秒后开新的（22:24:19、22:26:54），#56 里是先开新的、5 秒后才停旧的。
//   推的屏取最近开推的那路画面，两种都对
// - 停了的流在表里再留 restartGrace：加屏、撤屏时 UU 会停流再重开（2026-11-12 的日志），接管时前一台停了不到 1 秒新的一台才开（V12），
//   宽限内仍算在推、推的屏照旧
import Foundation
import SnugCore

package struct CaptureStreams: Sendable {
    /// 停了之后等这么久，没有重新开推才算真的停了
    package static let restartGrace: TimeInterval = 3

    private struct Stream: Sendable {
        /// 开推前最后描述的那块屏（UU 先枚举全部屏幕，再为要推的那块建过滤器、开推）
        let display: DisplayID?
        /// 登记了声音输出：UU 传声音的那一路
        let sound: Bool
        let started: Date
        var stopped: Date?

        /// 还开着，或停了还在宽限里
        func alive(at now: Date) -> Bool {
            stopped.map { now.timeIntervalSince($0) <= CaptureStreams.restartGrace } ?? true
        }
    }

    /// 按 SCStream 的地址记；地址之后给新开的流用时，开推那一刻整条换掉。过了宽限的流去掉，表不越记越长
    private var streams: [UInt64: Stream] = [:]
    /// 登记了声音输出、还没开推的流
    private var soundOutputs: Set<UInt64> = []
    private var lastDescribed: DisplayID?

    package init() {}

    package mutating func apply(_ record: CaptureLogRecord) {
        streams = streams.filter { $0.value.alive(at: record.date) }
        switch record.event {
        case .displayDescribed(let id):
            lastDescribed = id
        case .soundAdded(let stream):
            soundOutputs.insert(stream)
        case .captureStarted(let stream):
            streams[stream] = Stream(display: lastDescribed, sound: soundOutputs.remove(stream) != nil, started: record.date)
        case .captureStopped(let stream), .released(let stream):
            // 停和释放各打一句（停有时还重复一句），按第一句算
            if streams[stream]?.stopped == nil { streams[stream]?.stopped = record.date }
        }
    }

    package func isActive(at now: Date) -> Bool {
        streams.values.contains { $0.alive(at: now) }
    }

    /// 此刻 UU 在推的屏：最近开推的那路画面推的屏。没在推、只剩声音流、开推前没看到屏的描述时为 nil
    package func streamingDisplay(at now: Date) -> DisplayID? {
        streams.values.filter { !$0.sound && $0.alive(at: now) }.max { $0.started < $1.started }?.display
    }

    /// 日志监听（重新）启动时：先按时间回放启动前的日志（声音流只在远程开头开推一次，不回放就以为没在推），
    /// 再接上启动后收到的；两段重叠的部分按时间去掉。
    /// 启动前的日志只认 server（此刻的 UURemoteServer 进程）打的：进程崩溃时不留停流日志，上一个进程开的流
    /// 永远等不到「停」，放进来会一直算推流中。server 为 nil（没在运行）时启动前的日志一条不认
    package static func resumed(history: [CaptureLogRecord], live: [CaptureLogRecord], server: pid_t?) -> CaptureStreams {
        var streams = CaptureStreams()
        for r in history where server != nil && r.processID == server { streams.apply(r) }
        let after = history.last?.date ?? .distantPast
        for r in live where r.date > after { streams.apply(r) }
        return streams
    }
}
