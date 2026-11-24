import RemoteCrossDesk
import Testing

private func line(_ message: String, source: Bool = true) -> Substring {
    "[2026-11-23 18:52:52.825] [crossdesk] [info] \(source ? "[x.mm:426] " : "")\(message)"
}

private let started = line("Logger initialized", source: false)
private func found(_ index: Int, _ id: Int) -> Substring {
    line("macOS display discovered: index=\(index), display_id=\(id), name='屏 \(id)'")
}

@Suite("CrossDesk 这次启动认到的屏")
struct CrossDeskLaunchDisplaysTests {
    @Test("从实例开头起记认到的屏；别的句子不影响；新实例从头记")
    func followsLatestLaunch() {
        var launch = CrossDeskLaunchDisplays()
        #expect(launch.displays == nil)
        for l in [started, found(0, 1), found(1, 3), line("Requested display and system idle-sleep inhibition for screen sharing")] { launch.take(l) }
        #expect(launch.displays == [1, 3])
        launch.take(started)
        #expect(launch.displays == nil)
        launch.take(found(0, 1))
        #expect(launch.displays == [1])
    }

    @Test("换了进程：新进程启动那几句读到之前不算；没读到启动那句（滚动掉了）也照记认到的屏")
    func restartForgets() {
        var launch = CrossDeskLaunchDisplays()
        for l in [found(0, 1), found(2, 367)] { launch.take(l) }
        #expect(launch.displays == [1, 367])
        launch.restarted()
        #expect(launch.displays == nil)
    }
}
