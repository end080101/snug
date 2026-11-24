// 电脑屏资源库浮层里的内容：搜索框、「运行中 | 全部」、有事才出现的提示条、列表。
// 运行中按窗口在哪分三组，组名就是点下去会做的事（分组见 ComputerList）：「这块屏」切换（挪过来的另有「还原」），
// 「其他位置」放到这块屏（每行写明在哪），「没有窗口」打开；空的组连组名一起不显示。全部是本机 App 的图标网格。
// 搜索时结果不分页，多一组「未打开」，第一条高亮、回车执行。整行可点，动作字一直显示，不靠悬停提示。
// 这块屏做事时列表变淡、点不了，免得连着点出两件事。用 Mac 的字号和控件；说法和手机屏上的资源库一致
import SnugCore
import SnugSystem
import SwiftUI

@MainActor
@Observable
final class ComputerLibraryModel {
    enum Page: Hashable {
        case running, all
    }

    var open = false
    /// 这块屏还在就一直记着上次看的哪页
    var page = Page.running
    var query = ""
    /// 每次打开换一个：列表从头建，滚回顶部
    private(set) var session = 0

    func prepareForShow() {
        query = ""
        session += 1
    }
}

/// 浮层里点了什么，交给 ComputerLibrary（它决定动作做完收不收）
struct ComputerLibraryActions {
    let focus: (WindowInfo) -> Void
    let pull: (WindowInfo) -> Void
    let putBack: (WindowInfo) -> Void
    let open: (AppInfo) -> Void
    let dismiss: () -> Void
}

struct ComputerLibraryView: View {
    let id: ScreenID
    let state: AppState
    let catalog: AppCatalog
    @Bindable var model: ComputerLibraryModel
    let actions: ComputerLibraryActions
    @FocusState private var searching: Bool

    private var desk: Desk.State? { state.desks.desks[id] }
    private var query: String { model.query.trimmingCharacters(in: .whitespaces) }
    private var busy: Bool { desk?.work != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.s) {
            searchField
            Picker("", selection: $model.page) {
                Text("运行中").tag(ComputerLibraryModel.Page.running)
                Text("全部").tag(ComputerLibraryModel.Page.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!query.isEmpty)
            banner
            Group {
                if !query.isEmpty {
                    searchResults
                } else if model.page == .running {
                    running
                } else {
                    all
                }
            }
            .opacity(busy ? MotionTokens.disabledOpacity : 1)
            .disabled(busy)
            .id(model.session)
        }
        .padding(MacTokens.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PanelMaterial())
        .clipShape(RoundedRectangle(cornerRadius: MacTokens.Radius.sheet))
        .onExitCommand {
            if model.query.isEmpty { actions.dismiss() } else { model.query = "" }
        }
        .onChange(of: model.session, initial: true) { searching = true }
    }

    // MARK: 顶部

    private var searchField: some View {
        HStack(spacing: MacTokens.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索 App", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searching)
                .onSubmit {
                    // 和点一样：这块屏做事时不接，免得连着做两件事
                    guard !busy, !query.isEmpty, let item = firstUsable(in: groups(query)) else { return }
                    run(item)
                }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .font(.body)
        .padding(.horizontal, MacTokens.Space.s)
        .frame(height: 24)
        .background(MacTokens.Color.controlBackground, in: RoundedRectangle(cornerRadius: MacTokens.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: MacTokens.Radius.control).strokeBorder(MacTokens.Color.controlBorder))
    }

    /// 这块屏在做的事、出的问题；都没有就不占地方。下一个动作开始时、浮层收起时提示清掉
    @ViewBuilder private var banner: some View {
        if let work = desk?.work {
            HStack(spacing: MacTokens.Space.s) {
                ProgressView().controlSize(.small)
                Text(work.computerText).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .bannerStyle()
        } else if let notice = desk?.notice {
            HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MacTokens.Color.warning)
                VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                    Text(notice.text.headline).font(.body.weight(.semibold))
                    if let detail = notice.text.detail { Text(detail).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .bannerStyle()
        }
    }

    // MARK: 列表

    private var display: DisplayID? { desk?.display }

    private func groups(_ query: String) -> ComputerList.Groups {
        guard let display else { return ComputerList.Groups() }
        return ComputerList.groups(on: display, query: query, running: catalog.running, installed: catalog.installed, spots: catalog.spots)
    }

    @ViewBuilder private var running: some View {
        let groups = groups("")
        if !catalog.loaded {
            loading
        } else if groups.isEmpty {
            empty(symbol: "square.grid.2x2", title: "没有正在运行的 App", detail: nil)
        } else {
            list(groups, highlightFirst: false)
        }
    }

    @ViewBuilder private var searchResults: some View {
        let groups = groups(query)
        if groups.isEmpty, !catalog.installed.isEmpty {
            empty(symbol: "magnifyingglass", title: "无结果", detail: "没有与「\(query)」相符的 App 或窗口")
        } else {
            list(groups, highlightFirst: true, reading: catalog.installed.isEmpty)
        }
    }

    /// 列表里的一行，按点下去做的事分
    private enum Item: Equatable {
        case here(WindowInfo), elsewhere(WindowInfo), app(AppInfo)
    }

    /// 搜索时高亮、回车执行的那一条：从上往下第一条点得了的（正在关闭、正在退出的跳过）
    private func firstUsable(in g: ComputerList.Groups) -> Item? {
        let items = g.here.map(Item.here) + g.elsewhere.map(Item.elsewhere) + (g.windowless + g.unopened).map(Item.app)
        return items.first { item in
            switch item {
            case .here(let window), .elsewhere(let window): status(of: window) == nil
            case .app(let app): !quitting(app)
            }
        }
    }

    private func run(_ item: Item) {
        switch item {
        case .here(let window): actions.focus(window)
        case .elsewhere(let window): actions.pull(window)
        case .app(let app): actions.open(app)
        }
    }

    private func list(_ g: ComputerList.Groups, highlightFirst: Bool, reading: Bool = false) -> some View {
        let first = highlightFirst ? firstUsable(in: g) : nil
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: MacTokens.Space.m) {
                section("这块屏", g.here) { window in hereRow(window, highlighted: first == .here(window)) }
                section("其他位置", g.elsewhere) { window in elsewhereRow(window, highlighted: first == .elsewhere(window)) }
                section("没有窗口", g.windowless) { app in appRow(app, highlighted: first == .app(app)) }
                section("未打开", g.unopened) { app in appRow(app, highlighted: first == .app(app)) }
                if reading {
                    HStack(spacing: MacTokens.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("正在读取").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, MacTokens.Space.xs)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private func section<T: Identifiable, Row: View>(_ title: String, _ items: [T], @ViewBuilder row: @escaping (T) -> Row) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, MacTokens.Space.xs)
                    .padding(.bottom, MacTokens.Space.xxs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { row($0) }
            }
        }
    }

    // MARK: 行

    private func hereRow(_ window: WindowInfo, highlighted: Bool) -> some View {
        let fullScreen = display.map { ComputerList.location(of: window, spot: catalog.spots[window.key], on: $0) == .here(fullScreen: true) } == true
        let restorable = desk?.brought.contains(window.key) == true
        return ComputerRow(icon: catalog.icon(for: window), title: window.displayTitle,
                           subtitle: status(of: window) ?? (fullScreen ? "\(window.app) · 全屏" : window.app),
                           action: "切换", highlighted: highlighted, disabled: status(of: window) != nil,
                           run: { actions.focus(window) }) {
            if restorable {
                Button { actions.putBack(window) } label: {
                    Label("还原", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
                .disabled(status(of: window) != nil)
            }
        }
    }

    private func elsewhereRow(_ window: WindowInfo, highlighted: Bool) -> some View {
        ComputerRow(icon: catalog.icon(for: window), title: window.displayTitle,
                    subtitle: status(of: window) ?? "\(window.app) · \(whereText(window))",
                    action: "放到这块屏", highlighted: highlighted, disabled: status(of: window) != nil,
                    run: { actions.pull(window) }) { EmptyView() }
    }

    private func appRow(_ app: AppInfo, highlighted: Bool) -> some View {
        let quitting = quitting(app)
        return ComputerRow(icon: catalog.icon(for: app), title: app.name, subtitle: quitting ? "正在退出" : nil,
                           action: "打开", highlighted: highlighted, disabled: quitting,
                           run: { actions.open(app) }) { EmptyView() }
    }

    /// 窗口正在关、App 正在退出：行变灰、点不了
    private func status(of window: WindowInfo) -> String? {
        if state.desks.closing.contains(window.key) { return "正在关闭" }
        if state.desks.quitting.contains(window.key.pid) { return "正在退出" }
        return nil
    }

    private func quitting(_ app: AppInfo) -> Bool {
        catalog.running(app).map { state.desks.quitting.contains($0.pid) } == true
    }

    /// 别处的窗口在哪：最小化、别的 Snug 屏（写名字）、内建屏、外接屏（写屏名），别的桌面和全屏空间远端看不见，写「不在当前桌面」
    private func whereText(_ window: WindowInfo) -> String {
        guard let display else { return "不在当前桌面" }
        switch ComputerList.location(of: window, spot: catalog.spots[window.key], on: display) {
        case .minimized: return "已最小化"
        case .shown(let other):
            if let name = state.screenID(on: other).flatMap({ state.screen($0)?.name }) { return "在「\(name)」" }
            return CGDisplayIsBuiltin(other) != 0 ? "在内建屏" : "在「\(Screens.name(of: other))」"
        case .hidden, .here: return "不在当前桌面"
        }
    }

    // MARK: 全部

    @ViewBuilder private var all: some View {
        if catalog.installed.isEmpty {
            loading
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(MacTokens.Size.libraryGridItem), spacing: MacTokens.Space.s), count: 4),
                          spacing: MacTokens.Space.l) {
                    ForEach(catalog.installed) { installed in
                        let app = installed.app
                        let running = catalog.running(app)
                        let quitting = quitting(app)
                        Button { actions.open(app) } label: {
                            VStack(spacing: MacTokens.Space.xxs) {
                                Image(nsImage: catalog.icon(for: app)).resizable()
                                    .frame(width: MacTokens.Size.libraryGridIcon, height: MacTokens.Size.libraryGridIcon)
                                Text(app.name).font(.callout).lineLimit(1)
                                Circle().fill(.secondary).frame(width: 4, height: 4).opacity(running == nil ? 0 : 1)
                            }
                            .frame(width: MacTokens.Size.libraryGridItem)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(quitting)
                        .opacity(quitting ? MotionTokens.disabledOpacity : 1)
                        .accessibilityLabel(running == nil ? app.name : "\(app.name)，正在运行")
                    }
                }
                .padding(.top, MacTokens.Space.xs)
            }
        }
    }

    // MARK: 空、读取中

    private var loading: some View {
        VStack(spacing: MacTokens.Space.s) {
            ProgressView().controlSize(.small)
            Text("正在读取").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func empty(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: MacTokens.Space.xs) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一行：图标 ｜ 标题和第二行 ｜ 动作字（一直显示，悬停变强调色）｜ 可选的按钮。整行可点，悬停和搜索高亮是强调色浅底
private struct ComputerRow<Trailing: View>: View {
    let icon: NSImage
    let title: String
    let subtitle: String?
    let action: String
    let highlighted: Bool
    let disabled: Bool
    let run: () -> Void
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovering = false

    var body: some View {
        let lit = (hovering || highlighted) && !disabled
        HStack(spacing: MacTokens.Space.s) {
            Button(action: run) {
                HStack(spacing: MacTokens.Space.s) {
                    Image(nsImage: icon).resizable()
                        .frame(width: MacTokens.Size.libraryRowIcon, height: MacTokens.Size.libraryRowIcon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).lineLimit(1)
                        if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: MacTokens.Space.s)
                    Text(action).font(.callout).foregroundStyle(lit ? AnyShapeStyle(MacTokens.Color.accent) : AnyShapeStyle(.secondary))
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel([title, subtitle, action].compactMap { $0 }.joined(separator: "，"))
            trailing()
        }
        .padding(.horizontal, MacTokens.Space.xs)
        .frame(minHeight: MacTokens.Size.rowMinHeight)
        .background(lit ? MacTokens.Color.accentFill : .clear, in: RoundedRectangle(cornerRadius: MacTokens.Radius.control))
        .opacity(disabled ? MotionTokens.disabledOpacity : 1)
        .onHover { hovering = $0 }
    }
}

private extension View {
    func bannerStyle() -> some View {
        font(.callout)
            .padding(MacTokens.Space.s)
            .background(MacTokens.Color.fill, in: RoundedRectangle(cornerRadius: MacTokens.Radius.control))
    }
}

extension Desk.Work {
    /// 电脑屏资源库的进度：电脑屏只有打开 App、挪过来、还原、换比例几件事
    var computerText: String {
        switch self {
        case .opening(let app): "正在打开 \(app.name)…"
        case .placing(let window): "正在把 \(window.app) 挪过来…"
        case .puttingBack: "正在还原…"
        case .reshaping: "正在调整屏幕比例…"
        case .zooming, .dismissing: "请稍候…"
        }
    }
}
