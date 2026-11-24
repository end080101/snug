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

    @Test("选得到哪些屏：认到的还在线的都行；新屏不多于空出来的格（Snug 重启换了编号）按序号落上去也行；多了一律算选不到；没读到为 nil")
    func reachable() {
        var launch = CrossDeskLaunchDisplays()
        #expect(launch.reachable(online: [1, 3]) == nil)
        for l in [started, found(0, 24), found(1, 1), found(2, 3)] { launch.take(l) }
        #expect(launch.reachable(online: [24, 1, 3]) == [24, 1, 3])
        // Snug 重启，#24 换成 #25：那一格按序号落到 #25 上（11-23 实测 display mapping refreshed: slot=0, old_id=24, new_id=25）
        #expect(launch.reachable(online: [25, 1, 3]) == [25, 1, 3])
        // 又加了一块：格子不够，新屏选不到
        #expect(launch.reachable(online: [24, 25, 1, 3]) == [24, 1, 3])
        // 两块新屏只空出一格：哪块落上去看系统排序，Snug 不知道，宁可都算选不到
        #expect(launch.reachable(online: [25, 26, 1, 3]) == [1, 3])
        // CrossDesk 比 Snug 的屏先起来：没有空格
        launch.take(started)
        for l in [found(0, 1), found(1, 3)] { launch.take(l) }
        #expect(launch.reachable(online: [24, 1, 3]) == [1, 3])
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
