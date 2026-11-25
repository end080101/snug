import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

// 放着的窗口在 Snug 之外没了（手机上关掉、App 自己换了窗口、App 退出）：账不销，等它回来再还（issue #14）

private let code = WindowInfo(key: WindowKey(pid: 20, id: 30), app: "Visual Studio Code", bundleID: "com.microsoft.VSCode", title: "README.md — snug")
private let codeHome = CGRect(x: 150, y: 90, width: 1200, height: 800)
private let clash = WindowInfo(key: WindowKey(pid: 21, id: 31), app: "Clash Verge", bundleID: "io.github.clash-verge-rev.clash-verge-rev", title: "Clash Verge")
private let clashHome = CGRect(x: 265, y: 111, width: 940, height: 700)
private let zed = WindowInfo(key: WindowKey(pid: 22, id: 32), app: "Zed", bundleID: "dev.zed.Zed", title: "main.rs")
private let zedOther = WindowInfo(key: WindowKey(pid: 22, id: 33), app: "Zed", bundleID: "dev.zed.Zed", title: "lib.rs")
private let chat = WindowInfo(key: WindowKey(pid: 23, id: 50), app: "ChatGPT", bundleID: "com.openai.chat", title: "ChatGPT")
/// 窗口回到 Mac 原本的屏幕上、还是手机屏那么大（App 存下了手机屏上的大小）
private let phoneShaped = CGRect(x: 0, y: 33, width: phoneArea.width, height: phoneArea.height)

extension Rig {
    var leftBehind: [LeftBehind] { JSONFile<LeftBehindBook>(url: paths.leftBehind).loadOrQuarantine()?.entries ?? [] }

    /// 放上来以后它在 Snug 之外没了，定期核对时发现
    func vanishPlaced(_ w: WindowInfo) async {
        windows.vanish(w.key)
        desk.verifyPlacement()
        await desk.idle()
    }

    /// 远程结束、手机屏撤掉
    func endRemote() async {
        timeline.advance(10)
        desk.setWanted(false)
        await desk.idle()
        journal.clear()
    }

    func checkReturns() async {
        desk.checkReturns()
        await desk.idle()
    }
}

@MainActor
@Suite("留下的账 DeskSet")
struct DeskLeftBehindTests {
    @Test("放着的窗口在 Snug 之外关了：回到列表，主记录销掉、留下一笔账；VS Code 会按工作区记住字号，提示用户")
    func closedOutsideSnug() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
        #expect(rig.desk.state.closeButton == nil)
        #expect(rig.record == nil)
        #expect(rig.leftBehind.count == 1)
        #expect(rig.leftBehind.first?.record.original == codeHome)
        #expect(rig.leftBehind.first?.record.zoom == 2)
        #expect(rig.leftBehind.first?.record.filled == phoneArea)
        #expect(rig.desk.state.notice == .zoomLeftBehind(app: "Visual Studio Code", steps: 2))
    }

    @Test("Ghostty 关了：字号随窗口没了，不提示；账上记着大小")
    func liveWindowClosed() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        await rig.vanishPlaced(ghostty)
        #expect(rig.desk.state.notice == nil)
        #expect(rig.leftBehind.first?.record.filled == phoneArea)
    }

    @Test("远程结束后它带着手机屏上的大小回来了（VS Code 退出前存下了）：缩回字号、放回原位，账销掉")
    func returnedAfterRemote() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        await rig.endRemote()
        let back = WindowInfo(key: WindowKey(pid: 24, id: 40), app: code.app, bundleID: code.bundleID, title: code.title)
        rig.windows.add(back.key, frame: phoneShaped, info: back)
        await rig.checkReturns()
        #expect(rig.journal.all == ["zoom 40 -2 ∅", "move 40 \(codeHome.short) ∅"])
        #expect(rig.windows.window(back.key)?.frame == codeHome)
        #expect(rig.leftBehind.isEmpty)
    }

    @Test("回来时大小被 App 重设了（手机屏不在时 VS Code 用默认大小）：认不出是不是原样回来的，不碰，账留着")
    func returnedResized() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        await rig.endRemote()
        let back = WindowInfo(key: WindowKey(pid: 24, id: 40), app: code.app, bundleID: code.bundleID, title: code.title)
        rig.windows.add(back.key, frame: CGRect(x: 156, y: 33, width: 1200, height: 800), info: back)
        await rig.checkReturns()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.leftBehind.count == 1)
    }

    @Test("Clash 点关闭后从菜单栏重开（同一个编号、还是手机屏那么大）：放回原位，不调字号")
    func sameWindowReshown() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        await rig.vanishPlaced(clash)
        await rig.endRemote()
        rig.windows.add(clash.key, frame: phoneShaped, info: clash)
        await rig.checkReturns()
        #expect(rig.journal.all == ["move 31 \(clashHome.short) ∅"])
        #expect(rig.leftBehind.isEmpty)
    }

    @Test("飞书、微信点关闭只是把窗口收起来（窗口服务器里还在，辅助功能够不着）：算在 Snug 之外关了，转成留下的账；远程结束后 App 把它拿出来（编号没变、大小被系统改了）：放回原位")
    func withdrawnThenReshown() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.windows.withdraw(clash.key)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
        #expect(rig.record == nil)
        #expect(rig.leftBehind.first?.record.window == clash.key)
        await rig.endRemote()
        rig.windows.unhide(clash.key)
        rig.windows.setFrame(clash.key, CGRect(x: 0, y: 33, width: 1060, height: 900))
        await rig.checkReturns()
        #expect(rig.windows.window(clash.key)?.frame == clashHome)
        #expect(rig.leftBehind.isEmpty)
    }

    @Test("资源库开着时放着的窗口被收起来了：换放别的窗口不被它挡住、不提示无响应，它转成留下的账")
    func withdrawnBehindList() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.desk.showList()
        await rig.desk.idle()
        rig.windows.withdraw(clash.key)
        await rig.pull(finder)
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.desk.state.notice == nil)
        #expect(rig.leftBehind.first?.record.window == clash.key)
    }

    @Test("资源库开着时放着的窗口被收起来了，再点返回：按关了处理，资源库留着，不露出空桌面")
    func withdrawnThenReturnToPlaced() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.desk.showList()
        await rig.desk.idle()
        rig.windows.withdraw(clash.key)
        rig.desk.returnToPlaced()
        await rig.desk.idle()
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
        #expect(rig.leftBehind.first?.record.window == clash.key)
    }

    @Test("放着的窗口被收起来、确认的那一秒里又销毁了（App 退出时先收起窗口）：按关了处理，不当成最小化")
    func withdrawnThenDestroyed() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.windows.withdraw(clash.key)
        rig.windows.vanish(clash.key, at: rig.timeline.now + Desk.unshownConfirm / 2)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.placed == nil)
        #expect(rig.leftBehind.first?.record.window == clash.key)
    }

    @Test("远程结束后收起来的窗口全屏着拿出来（同一个编号）：先退出全屏再放回原位")
    func withdrawnReshownFullScreen() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.windows.withdraw(clash.key)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        await rig.endRemote()
        rig.windows.add(clash.key, frame: safariHome, fullScreen: true, windowed: phoneShaped, info: clash)
        await rig.checkReturns()
        #expect(rig.windows.window(clash.key)?.fullScreen == false)
        #expect(rig.windows.window(clash.key)?.frame == clashHome)
        #expect(rig.leftBehind.isEmpty)
    }

    @Test("收起来的窗口全屏着拿出来、又被放上手机屏：原位还按当初的，不改记成退出全屏后的位置")
    func withdrawnReshownFullScreenPlaced() async throws {
        let rig = try Rig()
        rig.windows.add(clash.key, frame: clashHome, info: clash)
        await rig.ready()
        await rig.pull(clash)
        rig.windows.withdraw(clash.key)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        rig.windows.add(clash.key, frame: safariHome, fullScreen: true, windowed: CGRect(x: 500, y: 300, width: 940, height: 700), info: clash)
        await rig.pull(clash)
        #expect(rig.desk.state.placed?.window == clash)
        #expect(rig.record?.original == clashHome)
        #expect(rig.leftBehind.isEmpty)
    }

    @Test("从资源库关掉本来就没显示的飞书窗口（最小化、App 被隐藏）：被收起来了也算关上，不提示无响应")
    func closeUnshownOnWithdrawingApp() async throws {
        let rig = try Rig()
        rig.windows.onClose(notes.key, .withdraws)   // 备忘录默认是最小化的
        rig.windows.onClose(ghostty.key, .withdraws)
        rig.windows.hide(ghostty.key)
        await rig.ready()
        for w in [notes, ghostty] {
            rig.desk.close(w)
            rig.timeline.advance(DeskSet.closeWait + 1)
            await rig.desk.idle()
            #expect(rig.desk.state.notice == nil)
            #expect(rig.desk.state.closing.isEmpty)
        }
    }

    @Test("放一个已被 App 收起来的窗口（资源库里还列着它）：提示已关闭，不提示无响应")
    func pullWithdrawn() async throws {
        let rig = try Rig()
        rig.windows.withdraw(finder.key)
        await rig.ready()
        await rig.pull(finder)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.notice == .windowGone(app: finder.app))
    }

    @Test("还在远程、手机上关了又在手机上重开（回到手机屏上）：接着放着，原位按当初的，带回来的字号不重复放大")
    func reopenedOnPhone() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        rig.journal.clear()
        let back = WindowInfo(key: WindowKey(pid: 20, id: 41), app: code.app, bundleID: code.bundleID, title: code.title)
        rig.windows.add(back.key, frame: phoneArea, info: back)
        await rig.checkReturns()
        #expect(rig.desk.state.placed?.window == back)
        #expect(rig.desk.state.placed?.zoom == 2)
        #expect(rig.desk.state.listVisible == false)
        #expect(!rig.journal.all.contains { $0.hasPrefix("zoom") })
        #expect(rig.record?.original == codeHome)
        #expect(rig.record?.window == back.key)
        #expect(rig.leftBehind.isEmpty)
        // 之后照常放回：缩回带回来的两级，回到当初的原位
        rig.journal.clear()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all.contains("zoom 41 -2 ✎"))
        #expect(rig.windows.window(back.key)?.frame == codeHome)
    }

    @Test("回到手机屏上时已经放着别的窗口：放回原位，不叠在手机屏上")
    func returnedWhileAnotherPlaced() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        await rig.pull(finder)
        rig.journal.clear()
        let back = WindowInfo(key: WindowKey(pid: 20, id: 41), app: code.app, bundleID: code.bundleID, title: code.title)
        rig.windows.add(back.key, frame: phoneArea, info: back)
        await rig.checkReturns()
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.journal.all == ["zoom 41 -2 ✎", "move 41 \(codeHome.short) ✎"])
    }

    @Test("Ghostty 退出后恢复的窗口（换了进程）不带放大：只放回原位；同一个进程里撤销关闭恢复的还带着：连字号一起缩回")
    func liveWindowReturns() async throws {
        for (pid, zoomBack) in [(Int32(60), false), (ghostty.key.pid, true)] {
            let rig = try Rig()
            await rig.ready()
            await rig.pull(ghostty)
            await rig.vanishPlaced(ghostty)
            await rig.endRemote()
            let back = WindowInfo(key: WindowKey(pid: pid, id: 70), app: ghostty.app, bundleID: ghostty.bundleID, title: ghostty.title)
            rig.windows.add(back.key, frame: phoneShaped, info: back)
            await rig.checkReturns()
            #expect(rig.journal.all == (zoomBack ? ["zoom 70 -2 ∅"] : []) + ["move 70 \(ghosttyHome.short) ∅"])
        }
    }

    @Test("Zed 的字号整个 App 共用：关了一个窗口，马上从它别的窗口缩回；没有别的窗口就等它再出窗口时缩回；进程没了就不欠")
    func appWideZoom() async throws {
        let zedApp = AppInfo(bundleID: "dev.zed.Zed", name: "Zed", path: nil)
        let rig = try Rig()
        rig.windows.add(zed.key, frame: codeHome, info: zed)
        rig.windows.add(zedOther.key, frame: clashHome, info: zedOther)
        _ = rig.apps.run(zedApp, pid: zed.key.pid)
        await rig.ready()
        await rig.pull(zed)
        rig.journal.clear()
        await rig.vanishPlaced(zed)
        #expect(rig.journal.all.contains("zoom 33 -2 ✎"))
        #expect(rig.desk.state.notice == nil)
        #expect(rig.leftBehind.first?.record.zoom == 0)

        // 没有别的窗口：账留着，不提示（之后会自动缩回，用户再按 ⌘- 就缩过头了）；它再出窗口时缩回
        let alone = try Rig()
        alone.windows.add(zed.key, frame: codeHome, info: zed)
        _ = alone.apps.run(zedApp, pid: zed.key.pid)
        await alone.ready()
        await alone.pull(zed)
        await alone.vanishPlaced(zed)
        #expect(alone.desk.state.notice == nil)
        #expect(alone.leftBehind.first?.record.zoom == 2)
        alone.journal.clear()
        alone.timeline.advance(Desk.replaceWait + 1)   // 过了跟随换窗口的时间，单看缩回
        alone.windows.add(zedOther.key, frame: clashHome, info: zedOther)
        await alone.checkReturns()
        #expect(alone.journal.all == ["zoom 33 -2 ∅"])
        #expect(alone.leftBehind.first?.record.zoom == 0)

        // 窗口没了是因为 Zed 退出了：内存里的字号跟着没了，什么都不欠
        let quit = try Rig()
        quit.windows.add(zed.key, frame: codeHome, info: zed)
        await quit.ready()
        await quit.pull(zed)
        await quit.vanishPlaced(zed)
        #expect(quit.desk.state.notice == nil)
        #expect(quit.leftBehind.first?.record.zoom == 0)
    }

    @Test("手机上点关闭按钮，飞书只是把窗口收起来：算关上了，不提示无响应")
    func closeButtonOnHidingApp() async throws {
        let rig = try Rig()
        rig.windows.onClose(finder.key, .withdraws)
        await rig.ready()
        await rig.pull(finder)
        rig.desk.closePlaced(window: finder.key.id)
        rig.timeline.advance(DeskSet.closeWait + 1)
        await rig.desk.idle()
        #expect(rig.desk.state.notice == nil)
        #expect(rig.desk.state.closing.isEmpty)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
    }

    @Test("关闭按钮只认放着的那个窗口；在问「要存储吗」的窗口不拦它的关闭按钮")
    func closeButtonOnlyForPlacedWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.desk.closePlaced(window: finder.key.id)   // 点按到这里时放着的已经换了
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.placed?.window == ghostty)
    }

    @Test("放回时 App 卡住、主记录还欠着的窗口，不被别的账认走（归启动或下次放窗口时按自己的记录还）")
    func pendingRecordNotClaimed() async throws {
        let rig = try Rig()
        let other = WindowInfo(key: WindowKey(pid: 20, id: 35), app: code.app, bundleID: code.bundleID, title: "notes — work")
        rig.windows.add(code.key, frame: codeHome, info: code)
        rig.windows.add(other.key, frame: clashHome, info: other)
        await rig.ready()
        await rig.pull(code)
        await rig.vanishPlaced(code)
        await rig.pull(other)
        rig.windows.blockZoom()
        await rig.endRemote()
        #expect(rig.record?.window == other.key)
        rig.windows.blockZoom(false)
        await rig.checkReturns()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.leftBehind.count == 1)
    }

    @Test("App 换了个窗口（ChatGPT 冷启动会换掉第一个窗口）：接着放上新窗口；放上来时就开着的窗口不算")
    func followsReplacement() async throws {
        let rig = try Rig()
        let other = WindowInfo(key: WindowKey(pid: 23, id: 52), app: chat.app, bundleID: chat.bundleID, title: "设置")
        rig.windows.add(chat.key, frame: codeHome, info: chat)
        rig.windows.add(other.key, frame: clashHome, info: other)
        await rig.ready()
        await rig.pull(chat)
        await rig.vanishPlaced(chat)
        await rig.checkReturns()
        #expect(rig.desk.state.placed == nil)   // 只有放上来时就开着的那个，不算换的

        let next = WindowInfo(key: WindowKey(pid: 23, id: 51), app: chat.app, bundleID: chat.bundleID, title: "ChatGPT")
        rig.windows.add(next.key, frame: CGRect(x: 486, y: 33, width: 540, height: 886), info: next)
        await rig.checkReturns()
        #expect(rig.desk.state.placed?.window == next)
        #expect(rig.record?.original == CGRect(x: 486, y: 33, width: 540, height: 886))
    }

    @Test("等满了才开出来的新窗口不接着放")
    func replacementTooLate() async throws {
        let rig = try Rig()
        rig.windows.add(chat.key, frame: codeHome, info: chat)
        await rig.ready()
        await rig.pull(chat)
        await rig.vanishPlaced(chat)
        rig.timeline.advance(Desk.replaceWait + 1)
        let next = WindowInfo(key: WindowKey(pid: 23, id: 51), app: chat.app, bundleID: chat.bundleID, title: "ChatGPT")
        rig.windows.add(next.key, frame: CGRect(x: 486, y: 33, width: 540, height: 886), info: next)
        await rig.checkReturns()
        #expect(rig.desk.state.placed == nil)
    }

    @Test("手机上点窗口自己的关闭按钮：先缩回字号、放回原位再关，不留账")
    func closeButtonGoesThroughSnug() async throws {
        let rig = try Rig()
        rig.windows.add(code.key, frame: codeHome, info: code)
        await rig.ready()
        await rig.pull(code)
        rig.journal.clear()
        rig.desk.closePlaced(window: code.key.id)
        await rig.desk.idle()
        #expect(rig.journal.all == ["zoom 30 -2 ✎", "move 30 \(codeHome.short) ✎", "close 30"])
        #expect(rig.windows.window(code.key) == nil)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.leftBehind.isEmpty)
        #expect(rig.desk.state.notice == nil)
    }

    @Test("上次崩溃留下的记录、窗口已经不在了：铺成过的留一笔账等它回来；旧版的记录（没记铺成的样子）照旧作废")
    func crashLeftoverGone() async throws {
        let rig = try Rig()
        rig.windows.vanish(ghostty.key)
        try RestoreRecord<PlacedRecord>(url: rig.paths.placedRecord(for: .phone)).record(
            PlacedRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, zoom: 2,
                        bundleID: ghostty.bundleID, title: ghostty.title, filled: phoneArea))
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.record == nil)
        #expect(rig.leftBehind.first?.record.original == ghosttyHome)

        let old = try Rig()
        old.windows.vanish(ghostty.key)
        try RestoreRecord<PlacedRecord>(url: old.paths.placedRecord(for: .phone)).record(
            PlacedRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, zoom: 2))
        old.desk.recover()
        await old.desk.idle()
        #expect(old.record == nil)
        #expect(old.leftBehind.isEmpty)
    }
}
