// 手势层的分派：原始事件 → 这家的整理 → 共用的翻译器 → 系统层照着执行的动作。纯值，不碰 CGEvent，可以单测。
// 这一按落在哪块范围里，在交给翻译器的按下那一刻按位置取，之后的拖动、抬起跟着这一下走（手指滑出范围也一样）
import CoreGraphics
import Foundation

/// 系统层照着执行的一步
public struct TouchStep: Equatable, Sendable {
    /// 原事件放不放行。超时拍没有原事件，这一项没有意义
    public var passOriginal = true
    /// 按顺序执行
    public var actions: [TouchAction] = []

    public init(passOriginal: Bool = true, actions: [TouchAction] = []) {
        self.passOriginal = passOriginal
        self.actions = actions
    }

    public static let pass = TouchStep()
}

public enum TouchAction: Equatable, Sendable {
    /// 原事件是被扣住的按下：留一份拷贝，之后 replayPress 补发它
    case holdOriginal
    /// 执行翻译器的指令；region 是这一按所在的范围（核对关闭按钮用）
    case perform(TouchCommand, in: TouchRegion?)
    /// 这一按结束：扣住的按下作废
    case dropHeld
}

public struct TouchPipeline: Sendable {
    private var normalizers: [any TouchNormalizer]
    private var translator = TouchTranslator()
    private var pressed: TouchRegion?

    /// 每个来源一份整理，下标就是来源号（系统层按注入进程认出是第几家）
    public init(normalizers: [any TouchNormalizer.Type]) {
        self.normalizers = normalizers.map { $0.init() }
    }

    /// 一次远程结束：各家整理、翻译器都从头来。整理记着的（手机端在发什么模式、扣着的移动）只对这次连接成立，
    /// 屏常驻（提前准备、设为主屏）时监听会跨多次远程，不清就带进下一次
    public mutating func reset() {
        self = TouchPipeline(normalizers: normalizers.map { type(of: $0) })
    }

    /// 监听要接哪几种原始事件：各家的并集
    public static func kinds(of normalizers: [any TouchNormalizer.Type]) -> Set<PointerEvent.Kind> {
        normalizers.reduce(into: []) { $0.formUnion($1.consumes) }
    }

    /// 惯性还在走：调用方按 Momentum.frameRate 定时调 momentumFrame()
    public var isCoasting: Bool { translator.isCoasting }

    public mutating func momentumFrame() -> ScrollStep? { translator.momentumFrame() }

    /// 下一次要喂超时拍的时刻：各家最早的那个
    public var deadline: TimeInterval? { normalizers.compactMap(\.deadline).min() }

    /// 一个原始事件。regions：此刻手势翻译管的范围
    public mutating func take(_ event: PointerEvent, from source: Int, regions: [TouchRegion]) -> TouchStep {
        guard normalizers.indices.contains(source), type(of: normalizers[source]).consumes.contains(event.kind) else { return .pass }
        var step = TouchStep()
        // 计时器晚到时先补上到点的输入，结果和准点一样
        if let due = normalizers[source].deadline, due <= event.time {
            feed(normalizers[source].tick(at: event.time), into: &step, regions: regions)
        }
        let normalized = normalizers[source].normalize(event)
        feed(normalized.before, into: &step, regions: regions)
        guard let current = normalized.current else { return step }
        let response = translate(current, regions: regions)
        if current.kind == .press, !response.passOriginal { step.actions.append(.holdOriginal) }
        step.actions += response.commands.map { .perform($0, in: pressed) }
        if current.kind == .release { step.actions.append(.dropHeld) }
        step.passOriginal = response.passOriginal
        return step
    }

    /// 超时拍：到点的整理交出该补的输入
    public mutating func tick(at time: TimeInterval, regions: [TouchRegion]) -> TouchStep {
        var step = TouchStep()
        for i in normalizers.indices {
            guard let due = normalizers[i].deadline, due <= time else { continue }
            feed(normalizers[i].tick(at: time), into: &step, regions: regions)
        }
        return step
    }

    private mutating func translate(_ input: TouchInput, regions: [TouchRegion]) -> TouchResponse {
        if input.kind == .press { pressed = regions.first { $0.frame.contains(input.location) } }
        return translator.handle(input, in: pressed)
    }

    /// 补出来的输入：没有原事件，补发按下、补发当前事件都无从做起（整理交出的输入不合语法才会走到，见 TouchGrammar）
    private mutating func feed(_ inputs: [TouchInput], into step: inout TouchStep, regions: [TouchRegion]) {
        for input in inputs {
            for command in translate(input, regions: regions).commands {
                guard command != .replayPress, command != .replayCurrent else {
                    Log.error("手势整理补出来的输入（\(input.kind)）要补发原事件（\(command)），可它没有原事件：跳过。整理交出的输入不合语法")
                    continue
                }
                step.actions.append(.perform(command, in: pressed))
            }
        }
    }
}
