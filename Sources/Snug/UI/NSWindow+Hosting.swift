// 更新窗口的搭法：SwiftUI 视图做内容，窗口高度跟着内容（进度变化）自动变；present、摆到哪块屏，设置、关于窗口也用
import AppKit
import SnugCore
import SnugSystem
import SwiftUI

extension NSWindow {
    convenience init(hosting view: some View, title: String) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        self.init(contentViewController: hosting)
        styleMask = [.titled, .closable]
        self.title = title
        isReleasedWhenClosed = false
        setContentSize(hosting.view.fittingSize)   // 先定尺寸再居中，否则按 0×0 居中会偏
        center()
    }

    /// 摆到这块屏正中（按可用区域，避开菜单栏、程序坞）
    func center(on screen: NSScreen) {
        let area = screen.visibleFrame
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
    }

    /// 从菜单栏打开时摆到点的那块屏上：在电脑屏的菜单栏点，远端的人才看得见。已经在这块屏上就不动，还在用户拖到的地方
    func bring(to display: DisplayID?) {
        guard let display, let screen = Screens.screen(for: display),
              !screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) else { return }
        center(on: screen)
    }

    /// 摆到最前。activating 为 false 时不激活 Snug：窗口照样浮在最前，但不抢走正在用的 App 的键盘焦点，
    /// 用户在别处按回车也不会误触窗口里的默认按钮（启动时的更新检查就这样弹）
    func present(activating: Bool) {
        if activating {
            NSApp.activate()
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }
}
