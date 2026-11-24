// --dump-remote crossdesk：打印从 CrossDesk 读到的东西和此刻的屏幕。只读，不碰 CrossDesk、不碰屏幕
import AppKit
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package enum CrossDeskDump {
    package static func run() -> Int32 {
        if let (url, version) = RemoteCheckTools.installedApp(bundleID: CrossDeskRemote.bundleID) {
            print("CrossDesk：\(url.path)（版本 \(version ?? "未知")，上次核对的是 \(CrossDeskRemote.verifiedVersion)）")
        } else {
            print("CrossDesk：没装（按 \(CrossDeskRemote.bundleID) 找不到）")
        }
        let processes = CrossDeskHost.processes()
        print("进程：" + (processes.isEmpty ? "没在运行" : processes.map { app in
            let start = app.launchDate.map { "启动于 \($0.formatted(date: .omitted, time: .standard))" } ?? "没有启动时间（开机自启或看门狗拉起）"
            return "\(app.processIdentifier)（\(app.executableURL?.path ?? "路径读不到")，\(start)）"
        }.joined(separator: "；")))
        let owners: [Int32]?
        do {
            owners = try CrossDeskHost.sharingOwners()
        } catch {
            print("电源断言：查不了（\(error)）")
            owners = nil
        }
        print("会话观测：\(CrossDeskRemote.observation(sharing: owners).evidence)")
        print("日志：\(CrossDeskLogs.directory.path)")
        // CrossDesk 只在启动时认屏：整份日志回放最近一次启动，各格此刻推的屏对照此刻的屏
        let instance = CrossDeskLogLine.lastInstance((CrossDeskLogs.lines() ?? []).compactMap { CrossDeskLogLine($0[...]) })
        print("最近一次启动（\(instance.first.map { String($0.stamp) } ?? "日志里没有")）认到的屏：")
        for line in instance {
            if case .displayFound(let index, let display, let name) = line.event { print("  [\(index)] #\(display) \(name)") }
        }
        var whole = CrossDeskSlots()
        instance.forEach { whole.take($0) }
        let online = Set(Screens.online() ?? [])
        let unreachable = { (slots: CrossDeskSlots) in
            slots.unreachable(online: online).map { $0.isEmpty ? "没有" : $0.sorted().map { "#\($0)" }.joined(separator: "、") } ?? "不知道"
        }
        print("各格此刻推的屏：\(whole.summary ?? "没认到")；此刻选不到：\(unreachable(whole))")
        // 运行时那条路（只读日志末尾、跟着新追加的行）：算出的格子应和上面整份回放的一致
        var tail = CrossDeskLogTail()
        var live = CrossDeskSlots()
        do {
            for line in try tail.poll() { live.take(line) }
            print("运行时读到的：\(live.summary ?? "没读到")；此刻选不到：\(unreachable(live))")
        } catch {
            print("运行时读不了日志：\(error)")
        }
        print("此刻的屏：")
        RemoteCheckTools.displayLines().forEach { print($0) }
        return owners == nil ? 1 : 0
    }
}
