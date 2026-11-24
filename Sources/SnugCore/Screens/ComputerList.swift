// 电脑屏 App 资源库的列表：窗口按相对这块屏在哪分组，点一个 App 做什么。全是纯逻辑，界面在 Snug/Computer。
// 分组就是动作：「这块屏」的窗口原地切换，「其他位置」的放过来，「没有窗口」的打开；
// 没在跑的 App 平时在「全部」网格里，只有搜索时作为「未打开」一组列出来
import CoreGraphics

public enum ComputerList {
    /// 窗口相对这块屏在哪
    public enum Location: Equatable, Sendable {
        /// 露在这块屏上；fullScreen：在这块屏的全屏空间里
        case here(fullScreen: Bool)
        case minimized
        /// 露在别的屏上
        case shown(DisplayID)
        /// 在别的桌面、别的屏的全屏空间里，或位置没读到：远端的人看不见
        case hidden

        public var isHere: Bool { if case .here = self { true } else { false } }
    }

    /// spot：窗口在哪块屏（AppCatalog.spots），没读到为 nil
    public static func location(of window: WindowInfo, spot: WindowSpot?, on display: DisplayID) -> Location {
        if window.minimized { return .minimized }
        switch spot {
        case .shown(display): return .here(fullScreen: false)
        case .fullScreen(display): return .here(fullScreen: true)
        case .shown(let other): return .shown(other)
        case .fullScreen, .hidden, nil: return .hidden
        }
    }

    public struct Groups: Equatable, Sendable {
        public var here: [WindowInfo] = []
        public var elsewhere: [WindowInfo] = []
        public var windowless: [AppInfo] = []
        /// 只在搜索时有：没在跑的 App
        public var unopened: [AppInfo] = []

        public init() {}

        public var isEmpty: Bool { here.isEmpty && elsewhere.isEmpty && windowless.isEmpty && unopened.isEmpty }
    }

    /// 列表按 running 的顺序（AppCatalog 已按最近用过排），同一个 App 的窗口可以分在不同组。
    /// query 不空时只列对上的：App 名对上列它全部的窗口（没窗口进「没有窗口」，没在跑进「未打开」），
    /// 只有窗口标题对上的只列那一个窗口（搜索规则同 AppList.search）
    public static func groups(on display: DisplayID, query: String, running: [RunningApp], installed: [InstalledApp],
                              spots: [WindowKey: WindowSpot]) -> Groups {
        let found = query.isEmpty ? nil : AppList.search(query, installed: installed, running: running)
        let apps = found.map { Set($0.apps.map(\.bundleID)) }
        let windows = Set(found?.windows.map(\.key) ?? [])
        var groups = Groups()
        for entry in running {
            let appMatches = apps?.contains(entry.app.bundleID) ?? true
            if entry.windows.isEmpty, appMatches { groups.windowless.append(entry.app) }
            for window in entry.windows where appMatches || windows.contains(window.key) {
                if location(of: window, spot: spots[window.key], on: display).isHere {
                    groups.here.append(window)
                } else {
                    groups.elsewhere.append(window)
                }
            }
        }
        if let found {
            let runningIDs = Set(running.map(\.app.bundleID))
            groups.unopened = found.apps.filter { !runningIDs.contains($0.bundleID) }
        }
        return groups
    }

    /// 点一个 App（「全部」网格里的图标、「没有窗口」「未打开」的行）做什么：同点程序坞图标，但窗口落在这块屏。
    /// 这块屏上已经有它的窗口就切换到最近用过的那个，少挪窗口；都在别处就把最近用过的放过来；没窗口、没在跑就打开
    public enum Action: Equatable, Sendable {
        case focus(WindowInfo)
        case pull(WindowInfo)
        case open(AppInfo)
    }

    public static func action(for app: AppInfo, on display: DisplayID, running: [RunningApp],
                              spots: [WindowKey: WindowSpot]) -> Action {
        let windows = running.first { $0.app.bundleID == app.bundleID }?.windows ?? []
        if let here = windows.first(where: { location(of: $0, spot: spots[$0.key], on: display).isHere }) { return .focus(here) }
        if let recent = windows.first { return .pull(recent) }
        return .open(app)
    }
}
