import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1,
                                closeButton: CloseButton(frame: CGRect(x: 8, y: 30, width: 14, height: 14), window: 7,
                                                         windowFrame: CGRect(x: 0, y: 22, width: 540, height: 900)))

private func event(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ t: Double) -> PointerEvent {
    PointerEvent(kind, at: CGPoint(x: x, y: y), time: t)
}

private func scrollPhases(_ step: TouchStep) -> [ScrollPhase] {
    step.actions.compactMap { if case .perform(.scroll(let s), _) = $0 { s.phase } else { nil } }
}

/// 假的整理：远控只发不按键的移动，第一下补按下并认作滑动，停 0.3 秒补抬起
private struct SlideFromMoves: TouchNormalizer {
    static let consumes: Set<PointerEvent.Kind> = [.move]
    var last: PointerEvent?

    mutating func normalize(_ event: PointerEvent) -> Normalized {
        defer { last = event }
        guard last != nil else {
            return Normalized(before: [TouchInput(.press, at: event.location, time: event.time),
                                       TouchInput(.recognized(.slide), at: event.location, time: event.time)], current: nil)
        }
        return Normalized(current: TouchInput(.drag, at: event.location, time: event.time))
    }

    var deadline: TimeInterval? { last.map { $0.time + 0.3 } }

    mutating func tick(at time: TimeInterval) -> [TouchInput] {
        guard let last else { return [] }
        self.last = nil
        return [TouchInput(.release, at: last.location, time: last.time)]
    }
}

/// 假的整理：一直有话要提醒用户
private struct Complains: TouchNormalizer {
    static let consumes: Set<PointerEvent.Kind> = [.move]
    mutating func normalize(_ event: PointerEvent) -> Normalized { .ignored }
    var advice: String? { "换个模式" }
}

/// 假的整理：什么都不管
private struct IgnoresAll: TouchNormalizer {
    static let consumes: Set<PointerEvent.Kind> = [.leftDown, .leftUp]
    mutating func normalize(_ event: PointerEvent) -> Normalized { .ignored }
}

/// 假的整理（不合语法）：一次移动补出完整的点一下，点击要补发原事件，可补出来的输入没有原事件
private struct TapFromMove: TouchNormalizer {
    static let consumes: Set<PointerEvent.Kind> = [.move]
    mutating func normalize(_ event: PointerEvent) -> Normalized {
        Normalized(before: [TouchInput(.press, at: event.location, time: event.time),
                            TouchInput(.release, at: event.location, time: event.time)], current: nil)
    }
}

@Suite("手势管线 TouchPipeline")
struct TouchPipelineTests {
    @Test("监听的事件种类取各家的并集；直通只要左键三种")
    func kinds() {
        #expect(TouchPipeline.kinds(of: [DirectTouch.self]) == [.leftDown, .leftDrag, .leftUp])
        #expect(TouchPipeline.kinds(of: [DirectTouch.self, SlideFromMoves.self]) == [.move, .leftDown, .leftDrag, .leftUp])
    }

    @Test("这家不吃这种事件、来源号对不上、整理说不管：原样放行，不碰翻译器")
    func ignored() {
        var p = TouchPipeline(normalizers: [DirectTouch.self, IgnoresAll.self])
        #expect(p.take(event(.move, 100, 300, 0), from: 0, regions: [phone]) == .pass)
        #expect(p.take(event(.leftDown, 100, 300, 0), from: 5, regions: [phone]) == .pass)
        #expect(p.take(event(.leftDown, 100, 300, 0), from: 1, regions: [phone]) == .pass)
        #expect(p.take(event(.leftUp, 100, 300, 0.1), from: 1, regions: [phone]) == .pass)
        // 翻译器没被碰过：直通的点一下照常
        #expect(p.take(event(.leftDown, 100, 300, 1), from: 0, regions: [phone]) == TouchStep(passOriginal: false, actions: [.holdOriginal]))
    }

    @Test("点一下：按下被扣住才留拷贝；抬起时先补发、最后作废拷贝；指令带着按下时的范围")
    func tapOrder() {
        var p = TouchPipeline(normalizers: [DirectTouch.self])
        #expect(p.take(event(.leftDown, 100, 300, 0), from: 0, regions: [phone]) == TouchStep(passOriginal: false, actions: [.holdOriginal]))
        #expect(p.take(event(.leftUp, 100, 300, 0.1), from: 0, regions: [phone])
                == TouchStep(passOriginal: false, actions: [.perform(.replayPress, in: phone), .perform(.replayCurrent, in: phone), .dropHeld]))
        // 屏外：放行，不留拷贝；抬起照样作废（本来就没有）
        #expect(p.take(event(.leftDown, 900, 300, 1), from: 0, regions: [phone]) == .pass)
        #expect(p.take(event(.leftUp, 900, 300, 1.1), from: 0, regions: [phone]) == TouchStep(passOriginal: true, actions: [.dropHeld]))
    }

    @Test("范围在交给翻译器的按下那一刻取：之后范围变了（屏撤了、换档），这一按照旧按原来的范围走；关闭按钮的指令带着那块范围")
    func regionAtPress() {
        var p = TouchPipeline(normalizers: [DirectTouch.self])
        _ = p.take(event(.leftDown, 15, 37, 0), from: 0, regions: [phone])
        #expect(p.take(event(.leftUp, 15, 37, 0.1), from: 0, regions: []).actions == [.perform(.closeWindow(at: CGPoint(x: 15, y: 37)), in: phone), .dropHeld])
    }

    @Test("补出来的输入先交翻译器：第一下移动补出按下和滑动，没有原事件要扣；之后的移动是滚动，原事件吞掉")
    func synthesizedSlide() {
        var p = TouchPipeline(normalizers: [SlideFromMoves.self])
        let first = p.take(event(.move, 100, 300, 0), from: 0, regions: [phone])
        #expect(first.passOriginal)
        #expect(!first.actions.contains(.holdOriginal))
        #expect(scrollPhases(first) == [.began])
        let next = p.take(event(.move, 100, 340, 0.02), from: 0, regions: [phone])
        #expect(!next.passOriginal)
        #expect(scrollPhases(next) == [.changed])
    }

    @Test("超时拍补出抬起：滚动收尾；到点前问 deadline 有值，收尾后没有")
    func tickEndsSlide() {
        var p = TouchPipeline(normalizers: [SlideFromMoves.self])
        _ = p.take(event(.move, 100, 300, 0), from: 0, regions: [phone])
        _ = p.take(event(.move, 100, 340, 0.02), from: 0, regions: [phone])
        #expect(p.deadline == 0.32)
        #expect(p.tick(at: 0.2, regions: [phone]) == TouchStep())
        #expect(scrollPhases(p.tick(at: 0.32, regions: [phone])) == [.ended])
        #expect(p.deadline == nil)
    }

    @Test("计时器晚到：下一个事件先补上到点的输入（上一段收尾），再处理这个事件（新的一段），结果和准点一样")
    func overdueDeadlineBeforeEvent() {
        var p = TouchPipeline(normalizers: [SlideFromMoves.self])
        // 慢慢挪（不带惯性），停住超过 0.3 秒后在别处又来一下
        _ = p.take(event(.move, 100, 300, 0), from: 0, regions: [phone])
        _ = p.take(event(.move, 100, 304, 0.2), from: 0, regions: [phone])
        #expect(scrollPhases(p.take(event(.move, 300, 600, 1), from: 0, regions: [phone])) == [.ended, .began])
    }

    @Test("补出来的输入要补发原事件（整理不合语法）：跳过这一条，扣住的按下照常补发")
    func synthesizedReplayCurrentDropped() {
        var p = TouchPipeline(normalizers: [TapFromMove.self])
        #expect(p.take(event(.move, 100, 300, 0), from: 0, regions: [phone]).actions == [.perform(.replayPress, in: phone)])
    }

    @Test("要提醒用户的话：按登记顺序第一家有话说的；都没话说为 nil（直通从不提醒）")
    func advice() {
        #expect(TouchPipeline(normalizers: [DirectTouch.self, IgnoresAll.self]).advice == nil)
        #expect(TouchPipeline(normalizers: [DirectTouch.self, Complains.self]).advice == "换个模式")
    }

    @Test("几家各用各的整理：一家的状态不影响另一家")
    func sourcesKeepOwnState() {
        var p = TouchPipeline(normalizers: [DirectTouch.self, SlideFromMoves.self])
        _ = p.take(event(.move, 100, 300, 0), from: 1, regions: [phone])
        #expect(p.take(event(.move, 100, 340, 0.02), from: 0, regions: [phone]) == .pass)
        #expect(scrollPhases(p.take(event(.move, 100, 380, 0.04), from: 1, regions: [phone])) == [.changed])
    }
}
