// Snug 自己的屏上用的面板：不激活 Snug、第一下点击就生效。手机、平板屏（ScreenWindows）和电脑屏（ComputerLibrary）共用
import AppKit
import SwiftUI

/// 不抢焦点、所有桌面和全屏空间里都在的面板，盖住菜单栏。手机、平板屏的资源库、小横条、截图浮层，电脑屏的小竖条和资源库浮层都用它。
/// 截图的浮层、电脑屏的两样是圆角的，面板透明（opaque 传 false）；电脑屏的不盖菜单栏，层级另设
final class ScreenPanel: NSPanel {
    init(content: NSView, opaque: Bool = true) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // 菜单栏是 24，菜单栏右边的图标是 25：再高一级才盖得住
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = opaque
        backgroundColor = opaque ? TouchTokens.Color.backgroundNSColor : .clear
        contentView = content
    }

    /// 平时点面板不让它变成键盘焦点：手机上的键盘输入要留给放上来的窗口；搜索、选型号时才打开
    var acceptsKeys = false {
        didSet {
            // 交还键盘：收起再摆回去才会让出焦点（resignKey 只是通知，调了也还是焦点）
            guard !acceptsKeys, isKeyWindow, isVisible else { return }
            orderOut(nil)
            orderFrontRegardless()
        }
    }

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }
}

/// 面板不是键盘焦点，第一下点击也要直接生效
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
