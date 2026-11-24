// CrossDesk 的适配器：每拍查一次电源断言判在场（见 CrossDeskRemote），同步；
// 再看一眼日志新长出来的行，跟着 CrossDesk 各格推哪块屏（它只在启动时认屏，见 CrossDeskLaunchDisplays），推算此刻选得到哪几块
import Foundation
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity
    /// 上一拍查不了电源断言：只在开始查不了、恢复时各记一次，不每拍刷日志
    private var unreadable = false
    private let tail = CrossDeskLogTail()
    private var launch = CrossDeskLaunchDisplays()
    /// 上一拍的 CrossDesk 进程；还没看过为 nil
    private var hosts: Set<Int32>?
    private var tailFailed = false

    package init() {}

    package func start() {}
    package func stop() {}

    package func sample(wallClock: Date) -> RemoteObservation {
        CrossDeskRemote.observation(sharing: sharingOwners(), reachable: reachableDisplays())
    }

    private func sharingOwners() -> [Int32]? {
        do {
            let owners = CrossDeskRemote.sharingOwners(in: try CrossDeskHost.assertions())
            if unreadable { Log.info("电源断言又查得到了：CrossDesk 的连接检测恢复") }
            unreadable = false
            return owners
        } catch {
            if !unreadable { Log.error("查不了电源断言（\(error)）：认不出 CrossDesk 的远程，之后每拍照查") }
            unreadable = true
            return nil
        }
    }

    /// CrossDesk 此刻选得到的屏；没在运行、还没读到、读不到在线的屏为 nil
    private func reachableDisplays() -> Set<DisplayID>? {
        let now = Set(CrossDeskHost.processes().map(\.processIdentifier))
        if let before = hosts, before != now {
            launch.restarted()
            Log.info("CrossDesk 进程：\(now.isEmpty ? "没在运行" : now.sorted().map(String.init).joined(separator: "、"))")
        }
        hosts = now
        do {
            let before = launch.slots
            for line in try tail.poll() { launch.take(line) }
            if tailFailed { Log.info("CrossDesk 的日志又读得到了") }
            tailFailed = false
            if launch.slots != before, let slots = launch.slots {
                Log.info("CrossDesk 各格推的屏：\(slots.sorted { $0.key < $1.key }.map { "第 \($0.key) 格 #\($0.value)" }.joined(separator: "、"))")
            }
        } catch {
            if !tailFailed { Log.error("读不了 CrossDesk 的日志（\(error)）：看不出它认到了哪几块屏") }
            tailFailed = true
        }
        guard !now.isEmpty, let online = Screens.online() else { return nil }
        return launch.reachable(online: Set(online))
    }
}
