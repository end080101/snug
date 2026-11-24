// CrossDesk 在本机的直接观测：进程、电源断言
import AppKit
import IOKit.pwr_mgt
import RemoteCrossDesk

enum CrossDeskHost {
    /// 运行中的 CrossDesk。按 bundle ID 认，不看 launchDate：开机自启（LaunchAgent 直接拉可执行文件）、看门狗 execv 重启的进程没有 launchDate
    static func processes() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: CrossDeskRemote.bundleID).filter { !$0.isTerminated }
    }

    struct AssertionsUnreadable: Error, CustomStringConvertible {
        let code: IOReturn
        var description: String { "IOPMCopyAssertionsByProcess 返回 \(String(format: "0x%08x", code))" }
    }

    /// 此刻每个进程持有的电源断言名
    static func assertions() throws -> [Int32: [String]] {
        var raw: Unmanaged<CFDictionary>?
        let code = IOPMCopyAssertionsByProcess(&raw)
        guard code == kIOReturnSuccess, let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            throw AssertionsUnreadable(code: code)
        }
        return byProcess.reduce(into: [:]) { result, entry in
            result[entry.key.int32Value] = entry.value.compactMap { $0[kIOPMAssertionNameKey] as? String }
        }
    }
}
