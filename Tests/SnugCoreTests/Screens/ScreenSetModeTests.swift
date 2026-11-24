import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

// 加屏、撤屏不动别的屏的模式（issue #13）。macOS 按「这组屏幕」各记一份模式，屏幕组合一变就把别的屏拨回它给新组合记的那份：
// 远程期间主屏的模式被临时改过（报告人那里是 30Hz，谁改的未确认），系统记在「没有手机屏的那组」名下；撤手机屏时组合变回去，主屏就被拨回去

private let redmi60 = ScreenMode(ioModeID: 12, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60)
private let redmi30 = ScreenMode(ioModeID: 13, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 30)
private let hp = ScreenMode(ioModeID: 5, width: 1080, height: 1920, pixelWidth: 1080, pixelHeight: 1920, refreshRate: 60)
private let builtIn = ScreenMode(ioModeID: 54, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)

@Suite("加屏、撤屏不动别的屏 ScreenSet")
@MainActor
struct ScreenSetModeTests {
    @Test("远程结束后撤屏，macOS 把别的屏拨回它给这组屏幕记的模式（远程期间临时改的 30Hz）：先设回撤屏前的样子、连永久配置一起写，再放回窗口；没被拨动的不碰")
    func retireKeepsOtherModes() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60, 3: hp]
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "retire 101", "mode 1 \(redmi60) 永久", "restore"])
        #expect(rig.displays.others == [1: redmi60, 3: hp])
    }

    @Test("显示器睡着时（Mac 锁屏）撤的屏要等唤醒才下线：下线前不动，下线那一刻 macOS 才拨动别的屏，这时再设回、放回窗口")
    func retireWaitsUntilOffline() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60]
        await rig.ready()
        rig.displays.staysOnline = true
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "retire 101"])
        #expect(rig.desk.state.screen == .off)
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "retire 101"])

        rig.displays.goOffline(101)
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "retire 101", "mode 1 \(redmi60) 永久", "restore"])
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("mode") }.count == 1)
    }

    @Test("旧屏还没下线又加了屏：不再等它，它下线时不按旧的样子去设")
    func newScreenSupersedesRetiring() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60]
        await rig.ready()
        rig.displays.staysOnline = true
        rig.desk.setWanted(false)
        await rig.desk.idle()
        rig.desk.setWanted(true)
        await rig.desk.idle()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.displays.goOffline(101)
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("mode") })
    }

    @Test("远程中撤屏（手机上退出手机屏）：撤屏前可能是远程用的临时模式，只对本次登录设回；远程结束、屏都醒着时，把别的屏此刻的模式写进永久配置")
    func retireDuringRemotePersistsAfterwards() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi30, 3: hp]
        rig.desk.setRemote(true)
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi60 }
        rig.desk.dismissScreen()
        await rig.desk.idle()
        #expect(rig.journal.all.contains("mode 1 \(redmi30)"))
        #expect(!rig.journal.all.contains { $0.hasSuffix("永久") })
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasSuffix("永久") })

        // 远程结束，UU 把主屏还原成 60Hz（只对本次登录）；屏还睡着时等着
        rig.journal.clear()
        rig.displays.others[1] = redmi60
        rig.displays.asleep = [1, 3]
        rig.desk.setRemote(false)
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        rig.displays.asleep = []
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all == ["mode 1 \(redmi60) 永久", "mode 3 \(hp) 永久"])
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.journal.all.count == 2)
    }

    @Test("提前准备的屏常驻：远程中撤过其中一块，远程结束后留下的都是常驻屏，照样把别的屏此刻的模式写进永久配置，写完不再空跑")
    func persistsWithPreparedScreens() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi30, 3: hp]
        var phone = rig.desk.wish
        phone.prepared = true
        let spec = ScreenSpec(name: "Snug 第二块", productID: ScreenSpec.portraitProductID,
                              serials: [200_100_000, 200_100_001, 200_100_002], maxPixels: ScreenFit.portraitPixels)
        let other = ScreenWish(id: ScreenID("second"), spec: spec, fit: .standard, behavior: .touchScreen, prepared: true)
        rig.set.setWishes([phone, other])
        await rig.set.idle()
        rig.desk.setRemote(true)
        rig.timeline.advance(10)
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi60 }
        rig.set.dismissScreen(other.id)
        await rig.set.idle()
        rig.journal.clear()
        rig.displays.others[1] = redmi60
        rig.set.setWishes([])
        rig.set.setWishes([phone])
        rig.desk.setRemote(false)
        await rig.set.idle()
        rig.desk.settleDisplays()
        await rig.set.idle()
        #expect(rig.journal.all.contains("mode 1 \(redmi60) 永久"))
        #expect(rig.journal.all.contains("mode 3 \(hp) 永久"))
        rig.journal.clear()
        rig.desk.settleDisplays()
        await rig.set.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.set.state.desks[.phone]?.screen == .ready(101))
    }

    @Test("设为主屏的那块常驻：远程中撤过别的屏，远程结束后常驻屏还在，照样把别的屏此刻的模式写进永久配置")
    func persistsWithResidentMain() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi30, 3: hp]
        var main = rig.desk.wish
        main.main = true
        let spec = ScreenSpec(name: "Snug 第二块", productID: ScreenSpec.portraitProductID,
                              serials: [200_100_000, 200_100_001, 200_100_002], maxPixels: ScreenFit.portraitPixels)
        let other = ScreenWish(id: ScreenID("second"), spec: spec, fit: .standard, behavior: .touchScreen)
        rig.desk.setRemote(true)
        rig.set.setWishes([main, other])
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi60 }
        rig.set.dismissScreen(other.id)
        await rig.set.idle()
        rig.journal.clear()
        // 远程结束，UU 把主屏还原成 60Hz；常驻的主屏还在
        rig.displays.others[1] = redmi60
        rig.set.setWishes([])
        rig.set.setWishes([main])
        rig.desk.setRemote(false)
        await rig.set.idle()
        rig.desk.settleDisplays()
        await rig.set.idle()
        #expect(rig.journal.all.contains("mode 1 \(redmi60) 永久"))
        #expect(rig.journal.all.contains("mode 3 \(hp) 永久"))
        #expect(rig.set.state.desks[.phone]?.screen == .ready(101))
    }

    @Test("加屏时也一样：别的屏被拨回这组屏幕上次记的模式，加好后设回加屏前的样子；远程中可能是临时模式，只对本次登录设回")
    func createKeepsOtherModes() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi30, 3: hp]
        rig.displays.onCreate = { [unowned displays = rig.displays] in displays.others[1] = redmi60 }
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "create", "mode 1 \(redmi30)", "restore"])
        #expect(rig.displays.others == [1: redmi30, 3: hp])
    }

    @Test("系统按分辨率、缩放、刷新率记模式，不记编号：编号重排了、属性没变不算拨动")
    func renumberedIsSame() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60]
        await rig.ready()
        var renumbered = redmi60
        renumbered.ioModeID = 99
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = renumbered }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("mode") })
        #expect(redmi60.isSame(as: renumbered))
        #expect(!redmi60.isSame(as: redmi30))
        var hiDPI = redmi60
        hiDPI.width = 1280
        hiDPI.height = 720
        #expect(!redmi60.isSame(as: hiDPI))
    }

    @Test("这期间拔掉的屏、新接上的屏都不碰；都没变就什么都不做")
    func onlyScreensPresentThroughout() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60, 3: hp]
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in
            displays.others[3] = nil
            displays.others[4] = builtIn
        }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("mode") })

        let calm = try Rig()
        calm.displays.others = [1: redmi60]
        calm.desk.setWanted(true)
        await calm.desk.idle()
        calm.desk.setWanted(false)
        await calm.desk.idle()
        #expect(!calm.journal.all.contains { $0.hasPrefix("mode") })
    }

    @Test("设不回去（帮手失败）只记日志，照样撤完屏")
    func modeFailureDoesNotBlock() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60]
        rig.displays.modeFails = true
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all.contains("mode 1 \(redmi60) 永久"))
        #expect(rig.desk.state.screen == .off)
    }

    @Test("模式在日志里写成点数、几倍、刷新率")
    func describesMode() {
        #expect("\(redmi30)" == "2560x1440 30Hz")
        #expect("\(builtIn)" == "1512x982（2 倍）120Hz")
        #expect("\(ScreenMode(ioModeID: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 59.94))" == "1920x1080 59.94Hz")
    }

    @Test("Snug 的屏多了，macOS 把外接屏挪开让地方，屏上的窗口跟着屏走：按屏挪过的距离算，不往回推；没跟着屏走的照样放回")
    func windowsFollowMovedDisplay() async throws {
        let rig = try Rig()
        let external = CGRect(x: -217, y: -1080, width: 1920, height: 1080)
        let shift: CGFloat = -191
        rig.displays.others = [5: hp]
        rig.displays.otherBounds = [5: external]
        // Ghostty 在外接屏上；Finder 在主屏上
        rig.windows.setFrame(ghostty.key, CGRect(x: 100, y: -900, width: 800, height: 600))
        rig.displays.onCreate = { [unowned displays = rig.displays, unowned windows = rig.windows] in
            displays.otherBounds[5] = external.offsetBy(dx: shift, dy: 0)
            windows.setFrame(ghostty.key, CGRect(x: 100 + shift, y: -900, width: 800, height: 600))   // 跟着屏走
            windows.setFrame(finder.key, CGRect(x: 0, y: 25, width: 800, height: 500))               // 系统把它挪了
        }
        await rig.ready()
        #expect(rig.windows.window(ghostty.key)?.frame == CGRect(x: 100 + shift, y: -900, width: 800, height: 600))
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
    }
}
