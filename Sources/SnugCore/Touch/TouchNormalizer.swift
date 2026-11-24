// 手势层的端口：各家远控发来的指针事件方言不同（有的发手指的按下、拖动、抬起，有的只发光标移动），
// 每家一个整理（TouchNormalizer），把自己的方言整理成标准手指输入（TouchInput），再交给共用的翻译器（TouchTranslator）。
// 核心只认标准手指输入，不认识任何一家；整理写在各家远控自己的纯逻辑目标里，在 RemoteIdentity 里声明。
// 分派在 TouchPipeline（纯值），读写 CGEvent 在系统层的 TouchTap
import CoreGraphics
import Foundation

/// 远控注入的一个原始指针事件：系统层从 CGEvent 读出的中性形态
public struct PointerEvent: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// 不按键的移动
        case move
        case leftDown, leftDrag, leftUp
    }

    public var kind: Kind
    /// 全局坐标（左上原点）
    public var location: CGPoint
    /// 单调时间（秒）：监听线程收到它的时刻
    public var time: TimeInterval

    public init(_ kind: Kind, at location: CGPoint, time: TimeInterval) {
        self.kind = kind
        self.location = location
        self.time = time
    }
}

/// 整理一个原始事件的结果
public struct Normalized: Equatable, Sendable {
    /// 先交给翻译器、没有对应原事件的输入：补出来的按下、抬起，远控已认出的手势
    public var before: [TouchInput]
    /// 这个原事件本身对应的输入；nil = 不归手势翻译管，原样放行
    public var current: TouchInput?

    public init(before: [TouchInput] = [], current: TouchInput?) {
        self.before = before
        self.current = current
    }

    /// 不归手势翻译管
    public static let ignored = Normalized(current: nil)
}

/// 一家远控的手势整理：把它注入的原始事件整理成标准手指输入。纯值类型，每次开监听新建一份。
/// 交出的输入要合标准语法（契约测试逐条查）：一次手势是 press、若干 drag、最多一个 recognized、一个 release；
/// 手势之间不重叠，时间不倒退
public protocol TouchNormalizer: Sendable {
    init()
    /// 要看哪几种原始事件：监听的事件掩码取各家的并集
    static var consumes: Set<PointerEvent.Kind> { get }
    mutating func normalize(_ event: PointerEvent) -> Normalized
    /// 下一次要喂超时拍的时刻（比如「停多久算松手」）；nil = 不用
    var deadline: TimeInterval? { get }
    /// 到了 deadline：交出到点该补的输入（比如补一个抬起）
    mutating func tick(at time: TimeInterval) -> [TouchInput]
}

extension TouchNormalizer {
    public var deadline: TimeInterval? { nil }
    public mutating func tick(at time: TimeInterval) -> [TouchInput] { [] }
}

/// 远控发的就是手指的按下、拖动、抬起（把手指当鼠标左键）：一对一交给翻译器，不改时间、不补、不等
public struct DirectTouch: TouchNormalizer {
    public static let consumes: Set<PointerEvent.Kind> = [.leftDown, .leftDrag, .leftUp]

    public init() {}

    public mutating func normalize(_ event: PointerEvent) -> Normalized {
        switch event.kind {
        case .leftDown: Normalized(current: TouchInput(.press, at: event.location, time: event.time))
        case .leftDrag: Normalized(current: TouchInput(.drag, at: event.location, time: event.time))
        case .leftUp: Normalized(current: TouchInput(.release, at: event.location, time: event.time))
        case .move: .ignored
        }
    }
}

/// 标准手指输入的语法，写成可以逐条核对的样子：契约测试和各家的回放测试拿它查整理交出的输入。
/// 一次手势：press，若干 drag，最多一个 recognized（在 release 之前），release；手势之间不重叠，时间不倒退
public struct TouchGrammar: Sendable {
    private var pressed = false
    private var recognized = false
    private var lastTime = -Double.infinity

    public init() {}

    /// 合语法返回 nil，否则返回哪里不对
    public mutating func check(_ input: TouchInput) -> String? {
        defer { lastTime = max(lastTime, input.time) }
        if input.time < lastTime { return "时间倒退：\(input.kind) @\(input.time) 早于 \(lastTime)" }
        switch input.kind {
        case .press:
            if pressed { return "上一下还没抬起又按下 @\(input.time)" }
            pressed = true
            recognized = false
        case .drag:
            if !pressed { return "没按下就拖动 @\(input.time)" }
        case .recognized:
            if !pressed { return "没按下就认出手势 @\(input.time)" }
            if recognized { return "一下里认出了两次手势 @\(input.time)" }
            recognized = true
        case .release:
            if !pressed { return "没按下就抬起 @\(input.time)" }
            pressed = false
        }
        return nil
    }
}
