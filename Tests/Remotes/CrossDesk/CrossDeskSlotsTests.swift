import RemoteCrossDesk
import Testing

private func line(_ message: String, source: Bool = true) -> Substring {
    "[2026-11-23 18:52:52.825] [crossdesk] [info] \(source ? "[x.mm:426] " : "")\(message)"
}

private let started = line("Logger initialized", source: false)
private func found(_ index: Int, _ id: Int) -> Substring {
    line("macOS display discovered: index=\(index), display_id=\(id), name='屏 \(id)'")
}
private func remapped(_ slot: Int, _ old: Int, _ new: Int) -> Substring {
    line("macOS display mapping refreshed: slot=\(slot), old_id=\(old), new_id=\(new), stream='Display\(slot + 1)'")
}

@Suite("CrossDesk 各格此刻推的屏")
struct CrossDeskSlotsTests {
    @Test("从实例开头起记认到的屏；别的句子不影响；新实例从头记；没读到启动那句（滚动掉了）也照记")
    func followsLatestLaunch() {
        var slots = CrossDeskSlots()
        #expect(slots.displays == nil)
        for l in [started, found(0, 1), found(1, 3), line("Requested display and system idle-sleep inhibition for screen sharing")] { slots.take(l) }
        #expect(slots.displays == [0: 1, 1: 3])
        #expect(slots.summary == "第 0 格 #1、第 1 格 #3")
        slots.take(started)
        #expect(slots.displays == nil)
        slots.take(found(0, 1))
        #expect(slots.displays == [0: 1])
        var rolled = CrossDeskSlots()
        for l in [found(0, 1), found(2, 367)] { rolled.take(l) }
        #expect(rolled.displays == [0: 1, 2: 367])
    }

    @Test("选不到哪些屏：格子推的还在线的都选得到；新屏不多于推着已下线屏的格（Snug 重启换了编号）按序号落上去也选得到；多了一律算选不到；没读到为 nil")
    func unreachable() {
        var slots = CrossDeskSlots()
        #expect(slots.unreachable(online: [1, 3]) == nil)
        for l in [started, found(0, 24), found(1, 1), found(2, 3)] { slots.take(l) }
        #expect(slots.unreachable(online: [24, 1, 3]) == [])
        // Snug 重启，#24 换成 #25：那一格按序号落到 #25 上（11-23 实测 display mapping refreshed: slot=0, old_id=24, new_id=25）
        #expect(slots.unreachable(online: [25, 1, 3]) == [])
        // 又加了一块：格子不够，新屏选不到
        #expect(slots.unreachable(online: [24, 25, 1, 3]) == [25])
        // 两块新屏只空出一格：哪块落上去看系统排序，Snug 不知道，宁可都算选不到
        #expect(slots.unreachable(online: [25, 26, 1, 3]) == [25, 26])
        // CrossDesk 比 Snug 的屏先起来：没有空格
        slots.take(started)
        for l in [found(0, 1), found(1, 3)] { slots.take(l) }
        #expect(slots.unreachable(online: [24, 1, 3]) == [24])
    }

    @Test("某一格改推了别的屏，跟着改：Snug 撤掉正推的屏，那格落到内建屏上，之后 Snug 再建的屏没格子；落回 Snug 的新屏也跟着记")
    func followsRemaps() {
        var slots = CrossDeskSlots()
        for l in [started, found(0, 27), found(1, 1), found(2, 3)] { slots.take(l) }
        // 11-23 实测：推着 #27 时 Snug 撤屏，CrossDesk 自动恢复到 #1；Snug 再建 #28，第 0 格仍推 #1，#28 选不到
        slots.take(remapped(0, 27, 1))
        #expect(slots.unreachable(online: [28, 1, 3]) == [28])
        slots.take(remapped(0, 1, 28))
        #expect(slots.unreachable(online: [28, 1, 3]) == [])
        // 刚连上时第一次抓屏（old_id=0）：照记
        slots.take(remapped(1, 0, 1))
        #expect(slots.displays == [0: 28, 1: 1, 2: 3])
    }
}
