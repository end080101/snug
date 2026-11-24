// UU远程 的身份。各处认 UU（感知、手势只接管它发来的操作、App 资源库里排除它）都认这里
import Foundation
import SnugCore

package enum UURemote {
    /// UU远程 主程序
    package static let bundleID = "com.netease.uuremote"
    /// 被远程时在本机注入鼠标键盘、推流、放覆盖窗口的进程
    package static let serverProcess = "UURemoteServer"

    /// 交给核心的身份：日志名「UU」让日志和抽出适配层之前逐字一样
    /// 连上时先推主屏：UU 只在连上那一刻选一次屏，选的是当时的主屏（11-18 实测，issue #28）
    package static let identity = RemoteIdentity(logName: "UU", displayName: "UU远程", bundleIDs: [bundleID],
                                                injector: InjectedEventSource(executableName: serverProcess), opensOnMainScreen: true)
}
