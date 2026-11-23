import RemoteCrossDesk
import Testing

@Suite("user 通过 CrossDesk 控制 Mac")
struct CrossDeskLogTests {
    // These records follow the local macOS 1.7.6 log. Values unrelated to capture are omitted.
    private let launch = "[2026-11-23 21:44:06.656] [crossdesk] [info] Logger initialized"
    private let connect = "[2026-11-23 21:44:45.735] [crossdesk] [info] [session_device_manager.cpp:345] Start screen capturer, show cursor: false"
    private let disconnect = "[2026-11-23 21:45:37.171] [crossdesk] [info] [connection_runtime.cpp:236] Last remote controller disconnected; recovering privacy, reason=connection_closed"
    private let stop = "[2026-11-23 21:45:37.602] [crossdesk] [info] [session_device_manager.cpp:357] Stop screen capturer"
    private let failure = "[2026-11-23 21:44:45.736] [crossdesk] [error] [session_device_manager.cpp:350] Start screen capturer failed: -1"
    private let cutoff = "2026-11-23 21:44:06.000"

    @Test("user 连入后 Snug 识别会话，最后一台控制端断开后识别结束")
    func incomingSession() {
        // Given a running Mac with the current CrossDesk log
        #expect(state([launch]) == false)
        // When a controller connects and later disconnects
        #expect(state([launch, connect]) == true)
        // Then the final controller's disconnect ends the observation, even before capture stops
        #expect(state([launch, connect, disconnect]) == false)
        #expect(state([launch, connect, disconnect, stop]) == false)
    }

    @Test("user 在连接中启动 Snug，已有会话仍然可见")
    func startsMidSession() {
        // Given capture has started, and unrelated capture reconfiguration follows
        let reconfiguration = "[2026-11-23 21:44:46.000] [crossdesk] [info] [screen_capturer_sck_impl.mm:565] Ignoring stale ScreenCaptureKit display refresh after stop"
        // When Snug reads the existing log
        // Then it sees the existing incoming session
        #expect(state([launch, connect, reconfiguration]) == true)
    }

    @Test("user 重启 CrossDesk 后，旧会话不会重新建屏")
    func restarts() {
        // Given an earlier instance went away while it was capturing
        // When the new instance starts or has yet to write its first record
        let newLaunch = "[2026-11-23 21:55:01.000] [crossdesk] [info] Logger initialized"
        // Then the old capture no longer counts as current
        #expect(state([launch, connect, newLaunch]) == false)
        #expect(CrossDeskLog.captureState(in: connect + "\n", since: "2026-11-23 21:55:00.000") == nil)
    }

    @Test("user 发起连接但抓屏失败时，Snug 不报告正在推流")
    func failedCapture() {
        // Given the host attempted to start capture
        // When the capturer reports that the attempt failed
        // Then there is no active capture
        #expect(state([launch, connect, failure]) == false)
    }

    @Test("user 只打开 CrossDesk 或主动控制其他电脑时，Snug 不建屏")
    func staysIdle() {
        // Given CrossDesk logged in and connected as a controller
        let outgoing = "[2026-11-23 21:44:46.000] [crossdesk] [info] [connection_runtime.cpp:666] Connecting to remote device"
        // When Snug polls with an incomplete trailing line
        // Then neither outgoing activity nor an incomplete record counts as capture
        #expect(CrossDeskLog.captureState(in: launch + "\n" + outgoing + "\n" + connect, since: cutoff) == false)
        #expect(state(["[2026-11-23 21:44:46.000] [another] [info] Start screen capturer, show cursor: false"]) == nil)
    }

    private func state(_ lines: [String]) -> Bool? {
        CrossDeskLog.captureState(in: lines.joined(separator: "\n") + "\n", since: cutoff)
    }
}
