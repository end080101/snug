// 一块电脑屏的 App 资源库：可见区左边缘竖直居中的小竖条，点开贴在它右边的浮层（ComputerLibraryView）。
// 两样都是不激活 Snug 的面板（ScreenPanel），所有桌面和全屏空间里都在；层级 .floating：盖住普通窗口，让着程序坞和菜单。
// 浮层什么时候收：
// - 点「切换」马上收；点「放到这块屏」「打开」等这块屏做完，没出提示才收，出了提示留着、重新拿回键盘
//   （做事时目标 App 会被激活、拿走焦点，这时不能因为失焦就收）；点「还原」不收，看着那一行回到「其他位置」
// - 按 Esc（有搜索词先清空）、再点小竖条、点浮层以外的地方（失焦；做事中失焦的同样等做完再按上一条收）；远控切去看别的屏、屏没了
// 浮层收起时还显示着的提示跟着清掉；收起后才出的进度和提示由小竖条接住（转圈、橙色三角）。
// 开着、远控在看这块屏时才要资源库的数据（带窗口在哪块屏），收起就不要
import AppKit
import SnugCore
import SnugSystem
import SwiftUI

@MainActor
final class ComputerLibrary: NSObject, NSWindowDelegate {
    let id: ScreenID
    private let state: AppState
    private let catalog: AppCatalog
    private let intents: any ComputerIntents
    private let model = ComputerLibraryModel()
    private let tab: ScreenPanel
    private let panel: ScreenPanel
    private var panelFrame = NSRect.zero
    /// 点了「放到这块屏」「打开」，或做事中失了焦：这块屏做完就收（没出提示的话）
    private var closeWhenDone = false
    private var screenObserver: (any NSObjectProtocol)?
    private var closed = false
    private var owner: String { "computer/\(id.rawValue)" }

    init(id: ScreenID, state: AppState, catalog: AppCatalog, intents: any ComputerIntents) {
        self.id = id
        self.state = state
        self.catalog = catalog
        self.intents = intents
        tab = ScreenPanel(content: NSView(), opaque: false)
        panel = ScreenPanel(content: NSView(), opaque: false)
        super.init()
        tab.level = .floating
        panel.level = .floating
        // 浮层要打字搜索，一直能当键盘焦点；它只在开着时露着，藏起来时成不了焦点。小竖条不要焦点，点它不会抢走浮层的键盘
        panel.acceptsKeys = true
        tab.hasShadow = true
        tab.contentView = FirstMouseHostingView(rootView: ComputerTabView(id: id, state: state, model: model) { [weak self] in
            self?.toggle()
        })
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = FirstMouseHostingView(rootView: ComputerLibraryView(
            id: id, state: state, catalog: catalog, model: model,
            actions: ComputerLibraryActions(
                focus: { [weak self] in self?.focus($0) },
                pull: { [weak self] in self?.pull($0) },
                putBack: { [weak self] in self?.intents.putBack($0.key) },
                open: { [weak self] in self?.open($0) },
                dismiss: { [weak self] in self?.dismiss(because: "Esc") })))
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        follow()
    }

    /// 屏没了、远程结束：拆掉，不再跟
    func close() {
        closed = true
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        dismiss(because: "屏撤掉了")
        tab.close()
        panel.close()
    }

    private func follow() {
        guard !closed else { return }
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.follow() } }
        }
    }

    private func update() {
        guard !closed else { return }
        let desk = state.desks.desks[id]
        guard let display = desk?.display, let screen = Screens.screen(for: display) else {
            // 屏在建、在换，或系统里还没有这块屏：先藏起来，屏好了（屏幕参数变化）再摆
            dismiss(because: "屏不在了")
            tab.orderOut(nil)
            return
        }
        layout(on: screen)
        if !tab.isVisible { tab.orderFrontRegardless() }
        guard model.open else { return }
        guard state.watching(id) else { return dismiss(because: "远控切去看别的屏") }
        let busy = desk?.work != nil
        catalog.want(owner, busy: busy, spots: true)
        if closeWhenDone, !busy {
            closeWhenDone = false
            finish()
        }
    }

    /// 小竖条贴可见区（已扣掉菜单栏和摆在这块屏上的程序坞）左边缘、竖直居中；浮层在它右边，以它为中心，四周离可见区留出边距
    private func layout(on screen: NSScreen) {
        let area = screen.visibleFrame
        let size = MacTokens.Size.self
        let edge = MacTokens.Space.l
        let tabFrame = NSRect(x: area.minX, y: area.midY - size.LibraryTab.height / 2, width: size.LibraryTab.width, height: size.LibraryTab.height)
        let height = min(size.LibraryPanel.maxHeight, area.height - edge * 2)
        let y = min(max(tabFrame.midY - height / 2, area.minY + edge), area.maxY - edge - height)
        panelFrame = NSRect(x: tabFrame.maxX + MacTokens.Space.s, y: y, width: size.LibraryPanel.width, height: height)
        if tab.frame != tabFrame { tab.setFrame(tabFrame, display: true) }
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
    }

    // MARK: 开、收

    private func toggle() {
        model.open ? dismiss(because: "再点小竖条") : show()
    }

    private func show() {
        guard state.desks.desks[id]?.display != nil else { return }
        model.prepareForShow()
        model.open = true
        panel.orderFrontRegardless()
        panel.makeKey()
        Log.info("屏（\(id)）的 App 资源库打开")
        update()
    }

    /// reason 写进日志：收起的路有好几条，浮层「自己收了」时从这里查
    private func dismiss(because reason: String) {
        closeWhenDone = false
        catalog.release(owner)
        guard model.open else { return }
        model.open = false
        Log.info("屏（\(id)）的 App 资源库收起：\(reason)")
        // 看过的提示收起时清掉；收起后才出的留给小竖条
        if state.desks.desks[id]?.notice != nil { intents.dismissNotice() }
        panel.orderOut(nil)
    }

    /// 做完了：没出提示就收，出了提示留着给人看，拿回键盘（点外面、按 Esc 照样能收）
    private func finish() {
        if state.desks.desks[id]?.notice == nil {
            dismiss(because: "做完了")
        } else {
            panel.makeKey()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard model.open, !closeWhenDone else { return }
        // 做事中失焦（目标 App 被激活，或人点了别处）：等做完再收，出了提示照样留着给人看（见 update、finish）
        if state.desks.desks[id]?.work != nil {
            closeWhenDone = true
        } else {
            dismiss(because: "点了别处")
        }
    }

    // MARK: 动作

    private func focus(_ window: WindowInfo) {
        intents.focus(window)
        dismiss(because: "切换")
    }

    private func pull(_ window: WindowInfo) {
        intents.pull(window)
        settle()
    }

    /// 点一个 App：这块屏上有它的窗口就切换，都在别处就放过来，没窗口就打开（见 ComputerList.action）
    private func open(_ app: AppInfo) {
        guard let display = state.desks.desks[id]?.display else { return }
        switch ComputerList.action(for: app, on: display, running: catalog.running, spots: catalog.spots) {
        case .focus(let window): focus(window)
        case .pull(let window): pull(window)
        case .open(let app):
            intents.open(app)
            settle()
        }
    }

    /// 动作已经交给这块屏：排上号了就等做完再收（屏没好也是排上号以后才发现，提示等做完再看）；
    /// 没排上号（只有正在退出的 App 的窗口，DeskSet.pull 不接）就按此刻的提示决定
    private func settle() {
        if state.desks.desks[id]?.work != nil {
            closeWhenDone = true
        } else {
            finish()
        }
    }
}
