// UU远程 兼容自检（scripts/snug remote-check uu → Snug --check-remote uu）：UU 一更新，把 Snug 依赖它的几处逐项核对，出一份报告。
// 这里只做判定，事实由系统部分（RemoteUUSystem 的 UUCheckRun）收集：UU 的安装与进程、抓屏和编码框架还链不链、
// 一段时间内 UU 的推流日志和 Snug 自己的日志。推流日志用正式运行的那套解析和状态（CaptureLogParser、CaptureSessionState）回放，
// 查的就是发出去的逻辑。只看日志、不碰 UU，所以要先用手机照常连一次，再回看
import Foundation
import SnugCore

package enum UUCheck {
    /// 最近一次核对过（自检无问题、手机实测无误）的 UU远程 版本，报告里拿它对照。核对完新版本后改这里
    package static let verifiedVersion = "4.48.1"
    /// UU 用它抓屏：推流日志里的屏描述、开始与停止都是它打的（见 CaptureLogParser）
    package static let captureFramework = "ScreenCaptureKit"
    /// UU 用它编码：编码会话的新建与结束用来判断推流中途是不是重启
    package static let encoderFramework = "VideoToolbox"
    /// Snug 记到的远程开始，前后这么久内 UU 日志里有推流开始，就算对上
    static let matchWindow: TimeInterval = 15

    package typealias Status = RemoteCheck.Status
    package typealias Item = RemoteCheck.Item

    /// 此刻的 UURemoteServer 进程
    package struct Server: Equatable, Sendable {
        package var pid: pid_t
        /// 进程启动的时刻；读不到为 nil
        package var start: Date?

        package init(pid: pid_t, start: Date?) {
            self.pid = pid
            self.start = start
        }
    }

    /// 系统部分（UUCheckRun）收集到的事实
    package struct Facts: Sendable {
        package var hours: Int
        /// 回看的起点（此刻往前 hours 小时）
        package var since: Date
        /// UU远程 的版本；没装为 nil
        package var version: String?
        package var appRunning: Bool
        /// 没在运行为 nil
        package var server: Server?
        /// 包里叫 UURemoteServer 的程序（包内路径）
        package var serverExecutables: [String]
        /// 框架名 → 链接它的程序（包内路径）
        package var linkers: [String: [String]]
        /// 回看时间内 UURemoteServer 的推流事件；系统日志读不出来为 nil
        package var capture: [CaptureLogRecord]?
        /// Snug 日志的原文（滚动过的旧日志在前）
        package var snugLog: [String]
        /// 此刻在线的 Snug 的屏：设为主屏的那块常驻，建屏的日志可能早在回看之前
        package var onlineSnugDisplays: Set<DisplayID>
        /// 此刻 UU 被控页的控制端表格；没读（没有辅助功能权限、UU 没在运行）为 nil
        package var controllersNow: ControllerTable?

        package init(hours: Int, since: Date, version: String?, appRunning: Bool, server: Server?, serverExecutables: [String],
                    linkers: [String: [String]], capture: [CaptureLogRecord]?, snugLog: [String], onlineSnugDisplays: Set<DisplayID>,
                    controllersNow: ControllerTable?) {
            self.hours = hours
            self.since = since
            self.version = version
            self.appRunning = appRunning
            self.server = server
            self.serverExecutables = serverExecutables
            self.linkers = linkers
            self.capture = capture
            self.snugLog = snugLog
            self.onlineSnugDisplays = onlineSnugDisplays
            self.controllersNow = controllersNow
        }
    }

    /// 实际拿来核对的那一段：只认此刻的 UURemoteServer 进程。UU 一更新就换进程，更新前的远程不能替新版本作证
    /// （正式运行也只认当前进程的推流记录，见 CaptureSessionState.resumed）
    struct Scope {
        /// 此刻的进程打的推流记录；日志读不出来为 nil
        var capture: [CaptureLogRecord]?
        /// 从核对起点之后的 Snug 日志摘出来的，屏编号并上此刻在线的 Snug 屏
        var snug: SnugLogDigest
        /// 「最近 4 小时」或「UURemoteServer 09:30 启动以来」
        var window: String

        init(_ f: Facts) {
            let restarted = f.server?.start.flatMap { $0 > f.since ? $0 : nil }
            window = restarted.map { "\(UURemote.serverProcess) \(UUCheck.clock($0)) 启动以来" } ?? "最近 \(f.hours) 小时"
            capture = f.capture.map { records in f.server.map { s in records.filter { $0.processID == s.pid } } ?? records }
            snug = SnugLogDigest(lines: f.snugLog, since: restarted ?? f.since, remote: UURemote.identity.logName)
            snug.snugDisplays.formUnion(f.onlineSnugDisplays)
        }
    }

    package static func evaluate(_ facts: Facts) -> [Item] {
        guard let version = facts.version else {
            return [Item(status: .fail, title: "UU远程", detail: "没装（按 \(UURemote.bundleID) 找不到），其余各项无从核对")]
        }
        let scope = Scope(facts)
        let note = version == verifiedVersion ? "即上次核对的版本" : "上次核对的是 \(verifiedVersion)"
        var items = [Item(status: .ok, title: "UU远程", detail: "版本 \(version)（\(note)）；核对范围：\(scope.window)")]
        items.append(process(facts))
        items.append(frameworks(facts))
        items += capture(scope)
        if let item = detection(scope.snug) { items.append(item) }
        if let item = controllers(scope.snug, now: facts.controllersNow) { items.append(item) }
        return items
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }


    // MARK: 逐项

    private static func process(_ f: Facts) -> Item {
        let name = UURemote.serverProcess
        guard !f.serverExecutables.isEmpty else {
            return Item(status: .fail, title: "后台进程", detail: "包里没有叫 \(name) 的程序：连接检测、推流日志、手势都按这个进程名认，改名即全部失效")
        }
        let paths = f.serverExecutables.joined(separator: "、")
        guard f.appRunning else { return Item(status: .warn, title: "后台进程", detail: "包里有 \(paths)；UU远程 没在运行，打开后再用手机连一次") }
        guard f.server != nil else { return Item(status: .warn, title: "后台进程", detail: "包里有 \(paths)，但没在运行：远程时由它推流、注入操作") }
        return Item(status: .ok, title: "后台进程", detail: "\(name) 在运行（\(paths)），手势按它认操作来源")
    }

    private static func frameworks(_ f: Facts) -> Item {
        let capture = f.linkers[captureFramework] ?? []
        let encoder = f.linkers[encoderFramework] ?? []
        guard !capture.isEmpty else {
            return Item(status: .fail, title: "推流框架",
                        detail: "没有程序链接 \(captureFramework)：UU 可能换了抓屏方式，推流日志会消失，连接检测与推流屏判断随之失效")
        }
        guard !encoder.isEmpty else {
            return Item(status: .warn, title: "推流框架",
                        detail: "没有程序链接 \(encoderFramework)：编码会话的日志会消失，推流中途重启时可能误判停流")
        }
        return Item(status: .ok, title: "推流框架",
                    detail: "\(captureFramework)：\(capture.joined(separator: "、"))；\(encoderFramework)：\(encoder.joined(separator: "、"))")
    }

    /// 推流日志能不能认出推流的开始，以及推的是哪块屏
    private static func capture(_ scope: Scope) -> [Item] {
        guard let records = scope.capture else {
            return [Item(status: .warn, title: "推流日志", detail: "读不出系统日志（log show 失败），推流相关各项无从核对")]
        }
        // 照正式运行的方式回放：每次推流开始时，此刻认定在推哪块屏
        var state = CaptureSessionState()
        var starts: [(date: Date, display: DisplayID?)] = []
        var stops = 0
        for record in records {
            state.apply(record)
            switch record.event {
            case .captureStarted: starts.append((record.date, state.streamingDisplay(at: record.date)))
            case .captureStopped: stops += 1
            default: break
            }
        }
        let sessions = scope.snug.sessionStarts
        guard !starts.isEmpty else {
            return sessions.isEmpty
                ? [Item(status: .warn, title: "推流日志", detail: "\(scope.window)没有远程，无从核对：用手机连一次（切到 Snug 的屏）再跑")]
                : [Item(status: .fail, title: "推流日志",
                        detail: "Snug 记到 \(sessions.count) 次远程，UU 日志里却没有一次可认的推流开始：写法可能变了，连接检测只剩提示窗口与控制端表格（原始日志见取证材料）")]
        }
        let matched = sessions.filter { s in starts.contains { abs($0.date.timeIntervalSince(s)) <= matchWindow } }.count
        let counts = "推流开始 \(starts.count) 次、停止 \(stops) 次"
        let log = matched < sessions.count
            ? Item(status: .warn, title: "推流日志", detail: "\(counts)；Snug 记到的 \(sessions.count) 次远程里 \(matched) 次对得上推流开始")
            : Item(status: .ok, title: "推流日志", detail: sessions.isEmpty ? counts : "\(counts)；Snug 记到的 \(sessions.count) 次远程都对得上")
        return [log, streamedDisplays(starts.compactMap(\.display), snug: scope.snug.snugDisplays)]
    }

    private static func streamedDisplays(_ displays: [DisplayID], snug: Set<DisplayID>) -> Item {
        guard !displays.isEmpty else {
            return Item(status: .fail, title: "推流屏",
                        detail: "推流开始前都没有可认的屏描述：认不出 UU 在推哪块屏，资源库刷新、面板与主屏判断都会出错")
        }
        var seen: [DisplayID] = []
        for d in displays where !seen.contains(d) { seen.append(d) }
        let list = seen.map { "#\($0)" }.joined(separator: "、")
        let mine = seen.filter(snug.contains)
        guard !mine.isEmpty else {
            return Item(status: .info, title: "推流屏", detail: "推过 \(list)；这段时间没推过 Snug 的屏，切屏能否认出待下次核对")
        }
        return Item(status: .ok, title: "推流屏", detail: "推过 \(list)，其中 Snug 的屏 \(mine.map { "#\($0)" }.joined(separator: "、"))：切到 Snug 的屏认得出")
    }

    /// Snug 连入时三路信号亮了哪几路。推流信号「未知」是 Snug 刚启动、日志监听还没回看完，不算 UU 的事。
    /// 远程过、日志里却一次连入都认不出，多半是 Snug 自己的日志写法改了：报出来，不悄悄略过这一项
    private static func detection(_ snug: SnugLogDigest) -> Item? {
        let all = snug.detections
        let logged = all.compactMap { UUSignals.logged($0.evidence) }
        let sessions = snug.sessionStarts.count
        if all.isEmpty {
            guard sessions > 0 else { return nil }
            return Item(status: .warn, title: "连接检测",
                        detail: "\(sessions) 次远程，Snug 日志里却没有一次「检测到 \(UURemote.identity.logName) 连入」：日志写法可能改了，无从核对")
        }
        let unreadable = all.count - logged.count
        let known = logged.filter { $0.capture != nil }
        let lit = known.filter { $0.capture == true }.count
        let overlay = logged.filter(\.overlay).count
        let unknown = logged.count - known.count
        let extra = "提示窗口 \(overlay) 次" + (unknown > 0 ? "；另有 \(unknown) 次连入时日志监听尚未就绪，不计" : "")
            + (unreadable > 0 ? "；\(unreadable) 次连入的信号快照读不出" : "")
        if known.isEmpty {
            guard unreadable > 0 else { return nil }
            return Item(status: .warn, title: "连接检测", detail: "\(all.count) 次连入都看不出推流信号（\(extra)）")
        }
        if lit == 0 {
            return Item(status: .fail, title: "连接检测",
                        detail: "\(known.count) 次连入推流信号一次都没亮：只靠提示窗口与控制端表格，容易漏判、误判断开（\(extra)）")
        }
        if lit < known.count || unreadable > 0 {
            return Item(status: .warn, title: "连接检测", detail: "\(known.count) 次连入里推流信号亮了 \(lit) 次（\(extra)）")
        }
        return Item(status: .ok, title: "连接检测", detail: "\(known.count) 次连入推流信号都亮了（\(extra)）")
    }

    /// 控制端名字：这段时间认出过哪些，加上此刻读到的表格
    private static func controllers(_ snug: SnugLogDigest, now table: ControllerTable?) -> Item? {
        let now: String = switch table {
        case .shown(let names): "此刻：\(names.joined(separator: "、"))"
        case .unrecognized: "此刻界面上没有控制端（不在远程，或 UU 停在别的页面）"
        case .unreadable: "此刻读不到 UU 的界面"
        case nil: "此刻没读界面（没有辅助功能权限，或 UU 没在运行）"
        }
        let sessions = snug.sessionStarts.count
        if !snug.controllers.isEmpty {
            return Item(status: .ok, title: "控制端", detail: "认出 \(snug.controllers.joined(separator: "、"))；\(now)")
        }
        if case .shown = table { return Item(status: .ok, title: "控制端", detail: now) }
        guard sessions > 0 else { return nil }
        return Item(status: .warn, title: "控制端",
                    detail: "\(sessions) 次远程都没认出控制端：UU 被控页可能改了版（UU 主窗口一直关着时也会这样）；\(now)")
    }
}
