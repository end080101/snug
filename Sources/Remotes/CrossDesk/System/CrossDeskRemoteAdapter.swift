// CrossDesk 的适配器：每拍查一次电源断言（见 CrossDeskRemote），同步、不读日志
import Foundation
import RemoteCrossDesk
import SnugCore

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity
    /// 上一拍查不了电源断言：只在开始查不了、恢复时各记一次，不每拍刷日志
    private var unreadable = false

    package init() {}

    package func start() {}
    package func stop() {}

    package func sample(wallClock: Date) -> RemoteObservation {
        CrossDeskRemote.observation(sharing: sharingOwners())
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
}
