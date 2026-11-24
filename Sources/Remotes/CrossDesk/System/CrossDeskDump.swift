// --dump-remote crossdesk：打印从 CrossDesk 读到的东西和此刻的屏幕。只读，不碰 CrossDesk、不碰屏幕
import AppKit
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package enum CrossDeskDump {
    package static func run() -> Int32 {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CrossDeskRemote.bundleID) {
            let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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
            owners = CrossDeskRemote.sharingOwners(in: try CrossDeskHost.assertions())
        } catch {
            print("电源断言：查不了（\(error)）")
            owners = nil
        }
        print("会话观测：\(CrossDeskRemote.observation(sharing: owners).evidence)")
        print("日志：\(CrossDeskLogs.directory.path)")
        // CrossDesk 只在启动时认屏：最近一次启动认到的，对照此刻的屏
        let instance = CrossDeskLogLine.lastInstance((CrossDeskLogs.lines() ?? []).compactMap { CrossDeskLogLine($0[...]) })
        print("最近一次启动（\(instance.first.map { String($0.stamp) } ?? "日志里没有")）认到的屏：")
        for line in instance {
            if case .displayFound(let index, let display, let name) = line.event { print("  [\(index)] #\(display) \(name)") }
        }
        print("此刻的屏：")
        RemoteCheckTools.displayLines().forEach { print($0) }
        return owners == nil ? 1 : 0
    }
}
