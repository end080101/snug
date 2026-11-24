// 电脑屏上 Snug 自己的东西：每块就绪的电脑屏一份 App 资源库（左边缘的小竖条，点开贴在旁边的浮层，见 ComputerLibrary）。
// 只在有人用 Snug 的屏时有（远程中、等重连、预览自测）：没人远程时电脑屏和原版 UU 一样，什么都不多。
// 和手机、平板屏的面板（ScreenPanels）平级、互不依赖；对外只经 ComputerIntents 动窗口，读 AppState 和 AppCatalog
import AppKit
import SnugCore

/// 电脑屏资源库要的动作，都落在这块屏上
@MainActor
protocol ComputerIntents: AnyObject {
    /// 这块屏上的窗口原地提到前面；已经离开这块屏就放过来（见 DeskSet.focus）
    func focus(_ window: WindowInfo)
    /// 放到这块屏：挪过来居中，不铺满、不调字号，记账、可还原
    func pull(_ window: WindowInfo)
    /// 打开 App（启动或唤回），新窗口放到这块屏
    func open(_ app: AppInfo)
    /// 把 Snug 挪过来的这个窗口放回原处
    func putBack(_ window: WindowKey)
    func dismissNotice()
}

@MainActor
final class ComputerScreens {
    private let state: AppState
    private let catalog: AppCatalog
    private let intents: (ScreenID) -> any ComputerIntents
    private var libraries: [ScreenID: ComputerLibrary] = [:]

    init(state: AppState, catalog: AppCatalog, intents: @escaping (ScreenID) -> any ComputerIntents) {
        self.state = state
        self.catalog = catalog
        self.intents = intents
        follow()
    }

    private func follow() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.follow() } }
        }
    }

    /// 每块就绪的电脑屏都挂，不管远控此刻在推哪块：没被推的屏谁都看不见，挂着无害；在远控里切过去时它已经在了
    private func update() {
        let ready = state.screensInUse ? Set(state.desks.desks.filter { $0.value.display != nil && !$0.value.behavior.touch }.keys) : []
        for id in libraries.keys where !ready.contains(id) {
            libraries.removeValue(forKey: id)?.close()
        }
        for id in ready where libraries[id] == nil {
            libraries[id] = ComputerLibrary(id: id, state: state, catalog: catalog, intents: intents(id))
        }
    }
}
