// 手势层和 CGEvent 之间的读写：接管哪几种事件、事件类型对应 PointerEvent 的哪一种、拼要补发的事件、打上记号发出去；
// InjectedEvents 认事件是哪家远控注入的。监听线程和按 TouchStep 执行在 TouchTap。
// 补发的事件打上记号：拷贝出来的事件保留远控的进程号，不打记号会被自己再接管一次，来回打转
import CoreGraphics
import Darwin
import Foundation
import SnugCore

enum TouchEvents {
    /// eventSourceUserData 里的记号（'SNUG'）
    private static let marker: Int64 = 0x534E_5547

    /// 监听的掩码：各家整理要看的事件种类（只有直通时是鼠标左键三种）
    static func mask(for kinds: Set<PointerEvent.Kind>) -> CGEventMask {
        kinds.reduce(CGEventMask(0)) { $0 | (1 << eventType(of: $1).rawValue) }
    }

    static func eventType(of kind: PointerEvent.Kind) -> CGEventType {
        switch kind {
        case .move: .mouseMoved
        case .leftDown: .leftMouseDown
        case .leftDrag: .leftMouseDragged
        case .leftUp: .leftMouseUp
        }
    }

    static func kind(of type: CGEventType) -> PointerEvent.Kind? {
        switch type {
        case .mouseMoved: .move
        case .leftMouseDown: .leftDown
        case .leftMouseDragged: .leftDrag
        case .leftMouseUp: .leftUp
        default: nil
        }
    }

    /// Snug 自己补发的事件
    static func isReplay(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// 打上记号再发：监听再看到它时原样放行
    static func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }

    /// 右键按下、抬起
    static func rightClick(at point: CGPoint) -> [CGEvent] {
        [CGEventType.rightMouseDown, .rightMouseUp].compactMap { type in
            let click = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)
            click?.setIntegerValueField(.mouseEventClickState, value: 1)
            return click
        }
    }

    /// 带相位的像素滚动：App 看到的和触控板两指滑动一样
    static func scroll(_ s: ScrollStep) -> CGEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: s.pixelsY, wheel2: s.pixelsX, wheel3: 0) else { return nil }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: s.phase.rawValue)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: s.momentum.rawValue)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: s.deltaY)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: s.deltaX)
        e.location = s.location
        return e
    }
}

/// 认远控注入的事件：按来源进程号查可执行文件路径，交给各家的 InjectedEventSource 判断，按进程号缓存。
/// 本机的触控板、鼠标不是它们发的，一律不认
struct InjectedEvents {
    let injectors: [InjectedEventSource]
    /// 查过的进程：第几家，nil = 不是远控
    private var known: [pid_t: Int?] = [:]

    init(injectors: [InjectedEventSource]) {
        self.injectors = injectors
    }

    /// 这个事件是第几家注入的（登记顺序）；不是远控注入的为 nil
    mutating func source(of event: CGEvent) -> Int? {
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else { return nil }
        if let cached = known[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        let path = length > 0 ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        let match = injectors.firstIndex { $0.matches(executablePath: path) }
        // 不能写 known[pid] = match：match 为 nil 时会删掉这一项，「查过、不是远控」就缓存不住
        known.updateValue(match, forKey: pid)
        return match
    }
}
