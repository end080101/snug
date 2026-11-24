// CrossDesk 兼容自检（scripts/snug remote-check crossdesk → Snug --check-remote crossdesk）：CrossDesk 一更新，把 Snug 依赖它的几处逐项核对。
// 这里只做判定，事实由系统部分（RemoteCrossDeskSystem 的 CrossDeskCheckRun）收集：CrossDesk 的安装与进程、程序里还有没有 Snug 认的那几句、
// 此刻的电源断言、一段时间内 CrossDesk 的日志和 Snug 自己的日志。只看、不碰 CrossDesk，所以要先用手机照常连一次（切到 Snug 的屏），再回看
import Foundation
import SnugCore

package enum CrossDeskCheck {
    /// CrossDesk 开始共享，前后这么久内 Snug 记到连入，就算认出来了
    static let matchWindow: TimeInterval = 15
    /// 没认出的时刻最多列这么多个
    static let listed = 5

    /// 系统部分（CrossDeskCheckRun）收集到的事实
    package struct Facts: Sendable {
        package var hours: Int
        /// 回看的起点（此刻往前 hours 小时）
        package var since: Date
        /// CrossDesk 的版本；没装为 nil
        package var version: String?
        /// 运行中的 CrossDesk 进程号
        package var processes: [Int32]
        /// 在 CrossDesk 的程序里找得到的句子（断言名、日志里认的几句，原文）
        package var foundInProgram: Set<String>
        /// 此刻持「共享桌面」断言的进程；查不了为 nil
        package var sharingNow: [Int32]?
        /// CrossDesk 日志的原文（旧的在前）；一份都读不到为 nil
        package var log: [String]?
        /// CrossDesk 日志的时间戳是这个时区的本地时间
        package var timeZone: TimeZone
        /// Snug 日志的原文（滚动过的旧日志在前）
        package var snugLog: [String]
        /// 此刻在线的屏：全部（含实体屏），和其中 Snug 的
        package var onlineDisplays: Set<DisplayID>
        package var onlineSnugDisplays: Set<DisplayID>

        package init(hours: Int, since: Date, version: String?, processes: [Int32], foundInProgram: Set<String>, sharingNow: [Int32]?,
                     log: [String]?, timeZone: TimeZone, snugLog: [String], onlineDisplays: Set<DisplayID>, onlineSnugDisplays: Set<DisplayID>) {
            self.hours = hours
            self.since = since
            self.version = version
            self.processes = processes
            self.foundInProgram = foundInProgram
            self.sharingNow = sharingNow
            self.log = log
            self.timeZone = timeZone
            self.snugLog = snugLog
            self.onlineDisplays = onlineDisplays
            self.onlineSnugDisplays = onlineSnugDisplays
        }
    }

    package static func evaluate(_ f: Facts) -> [RemoteCheck.Item] {
        guard let version = f.version else {
            return [RemoteCheck.Item(status: .fail, title: "CrossDesk", detail: "没装（按 \(CrossDeskRemote.bundleID) 找不到），其余各项无从核对")]
        }
        let note = version == CrossDeskRemote.verifiedVersion ? "即上次核对的版本" : "上次核对的是 \(CrossDeskRemote.verifiedVersion)"
        var items = [RemoteCheck.Item(status: .ok, title: "CrossDesk", detail: "版本 \(version)（\(note)）；核对范围：最近 \(f.hours) 小时")]
        items.append(process(f))
        items.append(sharing(f))
        items.append(phrases(f))
        let lines = f.log.map { $0.compactMap { CrossDeskLogLine($0[...]) } }
        items.append(sessions(lines, f))
        if let lines, let item = displays(CrossDeskLogLine.lastInstance(lines), f) { items.append(item) }
        return items
    }

    /// 回看起点之后的原文（取证材料里只放这一段）；不以时间戳开头的行跟着上一行走
    package static func recent(_ lines: [String], since: Date, in timeZone: TimeZone) -> [String] {
        var keep = false
        return lines.filter { line in
            if let date = CrossDeskLogLine.date(ofLine: line[...], in: timeZone) { keep = date >= since }
            return keep
        }
    }

    // MARK: 逐项

    private static func process(_ f: Facts) -> RemoteCheck.Item {
        guard !f.processes.isEmpty else {
            return RemoteCheck.Item(status: .warn, title: "进程", detail: "CrossDesk 没在运行：打开后再用手机连一次")
        }
        return RemoteCheck.Item(status: .ok, title: "进程", detail: "在运行（进程 \(f.processes.map(String.init).joined(separator: "、"))）")
    }

    /// 判在场全靠这条断言：程序里没了它、或者查不了，连接检测就失效
    private static func sharing(_ f: Facts) -> RemoteCheck.Item {
        let name = "「\(CrossDeskRemote.sharingAssertion)」"
        guard f.foundInProgram.contains(CrossDeskRemote.sharingAssertion) else {
            return RemoteCheck.Item(status: .fail, title: "会话信号",
                                    detail: "程序里找不到电源断言\(name)：CrossDesk 改了名或不再建它，Snug 认不出远程（连接检测全部失效）")
        }
        guard let owners = f.sharingNow else {
            return RemoteCheck.Item(status: .fail, title: "会话信号", detail: "查不了电源断言（IOPMCopyAssertionsByProcess 失败），Snug 认不出远程")
        }
        let now = owners.isEmpty ? "此刻没人远程" : "此刻有人远程（进程 \(owners.map(String.init).joined(separator: "、"))）"
        return RemoteCheck.Item(status: .ok, title: "会话信号", detail: "程序里有电源断言\(name)，Snug 按它判在场；\(now)")
    }

    /// 日志里认的那几句：只用来自检和认屏，判在场不靠它们，所以缺了只需留意
    private static func phrases(_ f: Facts) -> RemoteCheck.Item {
        let missing = CrossDeskLogLine.phrases.filter { !f.foundInProgram.contains($0) }
        guard missing.isEmpty else {
            return RemoteCheck.Item(status: .warn, title: "日志写法",
                                    detail: "程序里找不到 \(missing.map { "「\($0)」" }.joined(separator: "、"))：日志改了写法，自检和认屏跟着失灵（判在场不受影响）")
        }
        return RemoteCheck.Item(status: .ok, title: "日志写法", detail: "自检和认屏要认的 \(CrossDeskLogLine.phrases.count) 句程序里都有")
    }

    /// CrossDesk 每次开始共享，Snug 有没有记到连入
    private static func sessions(_ lines: [CrossDeskLogLine]?, _ f: Facts) -> RemoteCheck.Item {
        guard let lines else {
            return RemoteCheck.Item(status: .warn, title: "远程记录", detail: "读不到 CrossDesk 的日志（~/Library/Logs/CrossDesk），远程记录与认屏无从核对")
        }
        let dated = lines.compactMap { line in line.date(in: f.timeZone).map { (date: $0, event: line.event) } }.filter { $0.date >= f.since }
        let began = dated.filter { $0.event == .sharingBegan }.map(\.date)
        let detected = SnugLogDigest(lines: f.snugLog, since: f.since, remote: CrossDeskRemote.identity.logName).detections.map(\.date)
        if began.isEmpty {
            return detected.isEmpty
                ? RemoteCheck.Item(status: .warn, title: "远程记录", detail: "最近 \(f.hours) 小时没有远程，无从核对：用手机连一次（切到 Snug 的屏）再跑")
                : RemoteCheck.Item(status: .warn, title: "远程记录",
                                   detail: "Snug 记到 \(detected.count) 次连入，CrossDesk 日志里一次「开始共享」都没有：日志写法可能改了（判在场不受影响，认屏会受影响）")
        }
        let missed = began.filter { b in !detected.contains { abs($0.timeIntervalSince(b)) <= matchWindow } }
        let counts = "CrossDesk 开始共享 \(began.count) 次"
        guard missed.isEmpty else {
            let times = missed.prefix(listed).map { clock($0, in: f.timeZone) }.joined(separator: "、") + (missed.count > listed ? " 等" : "")
            return RemoteCheck.Item(status: .warn, title: "远程记录",
                                    detail: "\(counts)，Snug 认出 \(began.count - missed.count) 次；没认出的在 \(times)：Snug 当时开着的话就是连接检测出了问题（对照取证材料里的 snug.log）")
        }
        return RemoteCheck.Item(status: .ok, title: "远程记录", detail: "\(counts)，Snug 都认出了" + releaseDelay(dated))
    }

    /// 最后一台断开到放断言隔了多久：Snug 收尾就晚这么久
    private static func releaseDelay(_ dated: [(date: Date, event: CrossDeskLogLine.Event)]) -> String {
        var left: Date?
        var delays: [TimeInterval] = []
        for (date, event) in dated {
            switch event {
            case .lastControllerLeft: left = date
            case .sharingEnded:
                if let l = left { delays.append(date.timeIntervalSince(l)) }
                left = nil
            case .sharingBegan, .started: left = nil
            case .displayFound, .displayRemapped: break
            }
        }
        guard let longest = delays.max() else { return "" }
        return String(format: "；断开到放断言最长 %.1f 秒（Snug 收尾晚这么久）", longest)
    }

    /// CrossDesk 只在启动时认屏：此刻在线的 Snug 屏没有格子推、也落不到推着已下线屏的格上，就选不到（规则见 CrossDeskLaunchDisplays）
    private static func displays(_ instance: ArraySlice<CrossDeskLogLine>, _ f: Facts) -> RemoteCheck.Item? {
        guard let start = instance.first, start.event == .started else {
            return RemoteCheck.Item(status: .info, title: "认屏", detail: "CrossDesk 最近一次启动的日志已滚动掉，看不出它认到了哪几块屏")
        }
        var launch = CrossDeskLaunchDisplays()
        instance.forEach { launch.take($0) }
        let when = "CrossDesk \(start.date(in: f.timeZone).map { clock($0, in: f.timeZone) } ?? String(start.stamp)) 启动时"
        guard let slots = launch.slots, let reachable = launch.reachable(online: f.onlineDisplays.union(f.onlineSnugDisplays)) else {
            return RemoteCheck.Item(status: .warn, title: "认屏", detail: "\(when)没记下认到的屏：日志写法可能改了，认不出它看没看到 Snug 的屏")
        }
        let found = instance.compactMap { if case .displayFound(let index, let display, _) = $0.event { (index, display) } else { nil } }
        let moved = slots.filter { slot in found.first { $0.0 == slot.key }?.1 != slot.value }.sorted { $0.key < $1.key }
        let list = found.map { "#\($0.1)" }.joined(separator: "、") + moved.map { "，第 \($0.key) 格后来改推 #\($0.value)" }.joined()
        let snug = f.onlineSnugDisplays.sorted()
        guard !snug.isEmpty else {
            return RemoteCheck.Item(status: .info, title: "认屏", detail: "\(when)认到 \(list)；此刻没有 Snug 的屏，待下次核对")
        }
        let unseen = snug.filter { !reachable.contains($0) }
        guard unseen.isEmpty else {
            return RemoteCheck.Item(status: .warn, title: "认屏",
                                    detail: "\(when)认到 \(list)，此刻在线的 Snug 屏 \(unseen.map { "#\($0)" }.joined(separator: "、")) 没有格子推、也没有空出来的格：CrossDesk 选不到它，要重启 CrossDesk")
        }
        let renumbered = snug.filter { !Set(slots.values).contains($0) }
        guard renumbered.isEmpty else {
            return RemoteCheck.Item(status: .ok, title: "认屏",
                                    detail: "\(when)认到 \(list)；Snug 屏 \(renumbered.map { "#\($0)" }.joined(separator: "、")) 是重建后换的编号，按序号落在空出来的格上，选得到")
        }
        return RemoteCheck.Item(status: .ok, title: "认屏", detail: "\(when)认到 \(list)，此刻在线的 Snug 屏都有格子推")
    }

    private static func clock(_ date: Date, in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
