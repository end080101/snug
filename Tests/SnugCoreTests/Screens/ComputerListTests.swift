import Foundation
import Testing
@testable import SnugCore

private func app(_ bundle: String, _ name: String) -> AppInfo { AppInfo(bundleID: bundle, name: name, path: "/Applications/\(name).app") }
private func installed(_ bundle: String, _ name: String, english: String? = nil) -> InstalledApp {
    InstalledApp(app(bundle, name), english: english ?? name)
}
private func window(_ pid: Int32, _ id: UInt32, _ title: String, minimized: Bool = false) -> WindowInfo {
    WindowInfo(key: WindowKey(pid: pid, id: id), app: "App\(pid)", bundleID: "b.\(pid)", title: title, minimized: minimized)
}
private func running(_ pid: Int32, _ windows: [WindowInfo], bundle: String? = nil, name: String? = nil) -> RunningApp {
    RunningApp(pid: pid, app: app(bundle ?? "b.\(pid)", name ?? "App\(pid)"), windows: windows)
}

/// 这块屏是 #9，别的屏是 #10
private let here = window(1, 1, "本屏文档")
private let fullScreen = window(1, 2, "全屏")
private let elsewhere = window(1, 3, "构建日志")
private let minimized = window(1, 4, "已最小化", minimized: true)
private let unknown = window(4, 5, "位置未知")
private let notesApp = installed("com.apple.Notes", "备忘录", english: "Notes")
private let code = installed("com.microsoft.VSCode", "Visual Studio Code", english: "Code")
private let notesRunning = running(2, [], bundle: notesApp.app.bundleID, name: "备忘录")
private let apps = [running(1, [here, elsewhere, fullScreen, minimized]), notesRunning, running(4, [unknown])]
/// 最小化的窗口报成露在这块屏上也不算这块屏的（系统读到的是还原后的位置）
private let spots: [WindowKey: WindowSpot] = [here.key: .shown(9), fullScreen.key: .fullScreen(9), elsewhere.key: .shown(10),
                                              minimized.key: .shown(9)]

@Suite("电脑屏资源库 ComputerList")
struct ComputerListTests {
    @Test("按窗口在哪分组：露在这块屏、在它的全屏空间里的是「这块屏」；别的屏、最小化、位置没读到的是「其他位置」；同一个 App 的窗口可以分在两组")
    func groups() {
        let groups = ComputerList.groups(on: 9, query: "", running: apps, installed: [notesApp, code], spots: spots)
        #expect(groups.here == [here, fullScreen])
        #expect(groups.elsewhere == [elsewhere, minimized, unknown])
        #expect(groups.windowless == [notesRunning.app])
        #expect(groups.unopened.isEmpty)
    }

    @Test("搜索：只有标题对上的只列那个窗口；App 名对上的列它全部窗口，没窗口进「没有窗口」，没在跑进「未打开」")
    func search() {
        let byTitle = ComputerList.groups(on: 9, query: "构建", running: apps, installed: [notesApp, code], spots: spots)
        #expect(byTitle.here.isEmpty && byTitle.elsewhere == [elsewhere])
        #expect(byTitle.windowless.isEmpty && byTitle.unopened.isEmpty)
        let byName = ComputerList.groups(on: 9, query: "bwl", running: apps, installed: [notesApp, code], spots: spots)
        #expect(byName.windowless == [notesRunning.app] && byName.here.isEmpty && byName.elsewhere.isEmpty)
        let unopened = ComputerList.groups(on: 9, query: "code", running: apps, installed: [notesApp, code], spots: spots)
        #expect(unopened.unopened == [code.app] && unopened.windowless.isEmpty)
        #expect(ComputerList.groups(on: 9, query: "xyz", running: apps, installed: [notesApp, code], spots: spots).isEmpty)
    }

    @Test("窗口在哪：这块屏、全屏空间、最小化、别的屏、别的桌面和没读到")
    func location() {
        #expect(ComputerList.location(of: here, spot: .shown(9), on: 9) == .here(fullScreen: false))
        #expect(ComputerList.location(of: fullScreen, spot: .fullScreen(9), on: 9) == .here(fullScreen: true))
        #expect(ComputerList.location(of: minimized, spot: .shown(9), on: 9) == .minimized)
        #expect(ComputerList.location(of: elsewhere, spot: .shown(10), on: 9) == .shown(10))
        #expect(ComputerList.location(of: elsewhere, spot: .fullScreen(10), on: 9) == .hidden)
        #expect(ComputerList.location(of: unknown, spot: nil, on: 9) == .hidden)
    }

    @Test("点 App：这块屏上有它的窗口就切换（不先挪别处那个更近用过的），都在别处就放最近用过的，没窗口、没在跑就打开")
    func action() {
        let mixed = [running(1, [elsewhere, here])]
        #expect(ComputerList.action(for: mixed[0].app, on: 9, running: mixed, spots: spots) == .focus(here))
        let away = [running(1, [elsewhere, minimized])]
        #expect(ComputerList.action(for: away[0].app, on: 9, running: away, spots: spots) == .pull(elsewhere))
        #expect(ComputerList.action(for: notesRunning.app, on: 9, running: apps, spots: spots) == .open(notesRunning.app))
        #expect(ComputerList.action(for: code.app, on: 9, running: apps, spots: spots) == .open(code.app))
    }
}
