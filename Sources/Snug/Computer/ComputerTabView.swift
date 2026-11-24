// 电脑屏左边缘的小竖条：和手机、平板屏底部的小横条（chevron.compact.up）是一对，同属 chevron.compact 一族，箭头朝浮层弹出的方向。
// 只换图标和底色、不换大小：平时 chevron.compact.right；浮层开着 chevron.compact.left 加强调色浅底（再点收起）；
// 浮层收起后这块屏还在做事是小转圈，出了没看的提示是橙色三角（点开浮层，顶上就是那条提示）
import SnugCore
import SwiftUI

struct ComputerTabView: View {
    let id: ScreenID
    let state: AppState
    let model: ComputerLibraryModel
    let toggle: () -> Void

    private enum Look {
        case idle, open, working, notice
    }

    private var look: Look {
        let desk = state.desks.desks[id]
        if model.open { return .open }
        if desk?.work != nil { return .working }
        if desk?.notice != nil { return .notice }
        return .idle
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: MacTokens.Radius.libraryTab, topTrailingRadius: MacTokens.Radius.libraryTab)
        Button(action: toggle) {
            symbol
                .frame(width: MacTokens.Size.LibraryTab.width, height: MacTokens.Size.LibraryTab.height)
                .background(look == .open ? MacTokens.Color.accentFill : .clear)
                .background(PanelMaterial())
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("App 资源库")
        .help(help)
    }

    @ViewBuilder private var symbol: some View {
        let size = MacTokens.Size.libraryTabSymbol
        switch look {
        case .idle: Image(systemName: "chevron.compact.right").font(.system(size: size, weight: .semibold)).foregroundStyle(MacTokens.Color.label)
        case .open: Image(systemName: "chevron.compact.left").font(.system(size: size, weight: .semibold)).foregroundStyle(MacTokens.Color.accent)
        case .working: ProgressView().controlSize(.mini)
        case .notice: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: size)).foregroundStyle(MacTokens.Color.warning)
        }
    }

    /// 悬停提示（前台不是 Snug 时可能出不来，不靠它传达什么）
    private var help: String {
        let desk = state.desks.desks[id]
        switch look {
        case .working: return desk?.work?.computerText ?? "App 资源库"
        case .notice: return desk?.notice?.text.headline ?? "App 资源库"
        case .idle, .open: return "App 资源库"
        }
    }
}

/// 浮层和小竖条的底：菜单的毛玻璃材质，透出后面的窗口
struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
