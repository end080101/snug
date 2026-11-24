// 指针收拾（issue #29）：远控把指针留在虚拟屏的坐标上（UU 实测），屏一撤，那个坐标不再属于任何屏，指针就“不见了”；
// 断开后的重连等待期里屏还在、本机却看不见，同样找不回来。
// 落点怎么算见 SnugCore.CursorHome
import AppKit
import SnugCore

@MainActor
public enum Cursor {
    /// 把指针从这块屏上带走（撤屏前、断开后的重连等待期）：它还停在这块屏上时，落到另一块屏中央
    public static func leave(_ gone: DisplayID) {
        let area = CGDisplayBounds(gone)
        guard !area.isEmpty, let point = CGEvent(source: nil)?.location, area.contains(point) else { return }
        move(point, keepingOut: gone)
    }

    /// 不让指针停在这几块屏上（没人远程时看不见的屏）：滑进去了就退回别的屏上最近的那一点
    public static func keepOff(_ hidden: Set<DisplayID>) {
        guard let point = CGEvent(source: nil)?.location,
              hidden.contains(where: { CGDisplayBounds($0).contains(point) }) else { return }
        let visible = (Screens.online() ?? []).filter { !hidden.contains($0) }.map { CGDisplayBounds($0) }
        guard let landing = CursorHome.edge(pointer: point, visible: visible) else { return }
        CGWarpMouseCursorPosition(landing)
        Log.info("指针滑进了看不见的屏，退回 \(Int(landing.x)),\(Int(landing.y))（原来 \(Int(point.x)),\(Int(point.y))）")
    }

    private static func move(_ point: CGPoint, keepingOut gone: DisplayID) {
        let kept = (Screens.online() ?? []).filter { $0 != gone }.map { CGDisplayBounds($0) }
        let mainID = CGMainDisplayID()
        let main = mainID == gone ? .zero : CGDisplayBounds(mainID)
        guard let landing = CursorHome.landing(pointer: point, kept: kept, main: main) else { return }
        CGWarpMouseCursorPosition(landing)
        Log.info("指针不在留下的屏上，收回 \(Int(landing.x)),\(Int(landing.y))（原来 \(Int(point.x)),\(Int(point.y))）")
    }
}
