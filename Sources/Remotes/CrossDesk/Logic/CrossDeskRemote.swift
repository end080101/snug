// CrossDesk 的身份与观测。判在场看电源断言：有人远程时 CrossDesk 持一条「共享桌面」断言，
// 有入站控制端且在抓屏时建，停止抓屏时放（1.7.7 每拍按「有控制端且在抓屏」重设，screen_sharing_power.cpp、session_device_manager.cpp）。
// 不受日志滚动、时区、删日志、改措辞影响，查一次约 0.1ms；代价是断开后可能晚几秒才放（CrossDesk 认出断开要时间，实测最长 9.5 秒）。
// 不看进程：开机自启、看门狗拉起的 CrossDesk 没有 launchDate，断言照样认得出
import SnugCore

package enum CrossDeskRemote {
    package static let bundleID = "cn.crossdesk.app"
    package static let verifiedVersion = "v1.7.6-20261112"
    /// 被远程时注入鼠标事件的进程：主程序自己（CGEventPost，事件带 CROSSDES 记号）
    package static let injectorProcess = "CrossDesk"
    /// 有人远程时 CrossDesk 持有的电源断言名
    package static let sharingAssertion = "CrossDesk is sharing the desktop"
    package static let identity = RemoteIdentity(logName: "CrossDesk", displayName: "CrossDesk", bundleIDs: [bundleID],
                                                injector: InjectedEventSource(executableName: injectorProcess), normalizer: CrossDeskTouch.self)

    /// 电源断言（进程号 → 断言名）里持「共享桌面」断言的进程，按进程号排
    package static func sharingOwners(in assertions: [Int32: [String]]) -> [Int32] {
        assertions.filter { $0.value.contains(sharingAssertion) }.keys.sorted()
    }

    /// owners：持「共享桌面」断言的进程；查不了电源断言为 nil（不算在场）
    package static func observation(sharing owners: [Int32]?) -> RemoteObservation {
        let evidence = owners.map { $0.isEmpty ? "共享断言=无" : "共享断言=有（进程 \($0.map(String.init).joined(separator: "、"))）" } ?? "共享断言=查不了"
        return RemoteObservation(present: owners?.isEmpty == false, controllers: [], streamedDisplay: nil, evidence: evidence)
    }
}
