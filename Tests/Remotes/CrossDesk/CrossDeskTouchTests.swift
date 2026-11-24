import CoreGraphics
import Foundation
import Testing
@testable import RemoteCrossDesk
import SnugCore

private func e(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ t: Double) -> PointerEvent {
    PointerEvent(kind, at: CGPoint(x: x, y: y), time: t)
}

/// 整理交出的输入（不经翻译器），超时拍按 deadline 准点喂
private struct Run {
    var touch = CrossDeskTouch()
    var inputs: [TouchInput] = []
    var ignored: [PointerEvent] = []

    mutating func feed(_ events: [PointerEvent]) {
        for event in events {
            advance(to: event.time)
            let n = touch.normalize(event)
            inputs += n.before
            if let current = n.current { inputs.append(current) } else { ignored.append(event) }
        }
    }

    mutating func advance(to t: TimeInterval) {
        while let due = touch.deadline, due <= t { inputs += touch.tick(at: due) }
    }

    var kinds: [TouchInput.Kind] { inputs.map(\.kind) }
}

/// 让整理认出「绝对鼠标」：点一下，过一会儿在 80 点开外开始一下（开头跳到手指落点）
private func fingerWarmUp() -> [PointerEvent] {
    [e(.move, 100, 100, 0), e(.leftDown, 100, 100, 0.0005), e(.leftUp, 100, 100, 0.001), e(.move, 300, 400, 1)]
}

@Suite("CrossDesk 的手势整理")
struct CrossDeskTouchTests {
    // MARK: 点按、长按、虚拟鼠标键

    @Test("点一下（移动、左键按下、抬起同时到）：交翻译器按下、抬起，不带「认出长按」")
    func tap() {
        var run = Run()
        run.feed([e(.move, 200, 300, 1), e(.leftDown, 200, 300, 1.0005), e(.leftUp, 200, 300, 1.002)])
        #expect(run.kinds == [.press, .release])
        #expect(run.ignored.map(\.kind) == [.move])
    }

    @Test("长按不动松手：按下后 0.15 秒（加上客户端认长按的 0.35 秒，满 0.5 秒）还没抬起就是长按；差一点的还是点")
    func holdRelease() {
        var held = Run()
        held.feed([e(.move, 200, 300, 1), e(.leftDown, 200, 300, 1.0005), e(.leftUp, 200, 300, 1.16)])
        #expect(held.kinds == [.press, .recognized(.hold), .release])
        var quick = Run()
        quick.feed([e(.move, 200, 300, 1), e(.leftDown, 200, 300, 1.0005), e(.leftUp, 200, 300, 1.14)])
        #expect(quick.kinds == [.press, .release])
        #expect(CrossDeskTouch.holdAfterDown == TouchTranslator.holdDuration - 0.35)
    }

    @Test("长按后拖：第一下拖动前告诉翻译器「认出长按」，只说一次，不论按下多久就拖")
    func holdDrag() {
        var run = Run()
        run.feed([e(.move, 200, 300, 1), e(.leftDown, 200, 300, 1.0005), e(.leftDrag, 210, 300, 1.05),
                  e(.leftDrag, 240, 300, 1.07), e(.leftUp, 240, 300, 1.3)])
        #expect(run.kinds == [.press, .recognized(.hold), .drag, .drag, .release])
    }

    @Test("虚拟鼠标键（左键按下前没有同一点、紧挨着的移动）：按下、拖动、抬起都原样放行，不交翻译器")
    func virtualButton() {
        for lead in [nil, CGPoint(x: 200, y: 300), CGPoint(x: 260, y: 300)] as [CGPoint?] {
            var run = Run()
            let before = lead.map { [PointerEvent(.move, at: $0, time: lead == CGPoint(x: 200, y: 300) ? 0.9 : 0.999)] } ?? []
            run.feed(before + [e(.leftDown, 200, 300, 1), e(.leftDrag, 230, 300, 1.2), e(.leftUp, 230, 300, 1.4)])
            #expect(run.inputs.isEmpty, "前面的移动：\(String(describing: lead))")
        }
    }

    // MARK: 认出手机端在发什么

    @Test("刚开监听看不出是哪种模式：不按键的移动原样放行（光标照走），点按照样交翻译器")
    func unknownPassesMoves() {
        var run = Run()
        run.feed([e(.move, 100, 100, 0), e(.move, 120, 110, 0.02), e(.move, 140, 120, 0.04)])
        #expect(run.touch.feed == .unknown)
        #expect(run.inputs.isEmpty)
    }

    @Test("一下的开头跳到别处（手指落点）：认作绝对鼠标；连续 3 下开头都在上一个事件那一点（光标处）：认作相对鼠标")
    func feedVotes() {
        var run = Run()
        run.feed(fingerWarmUp())
        #expect(run.touch.feed == .finger)
        // 相对鼠标：点在光标处、滑动从光标处开始
        let p = CGPoint(x: 300, y: 400)
        run.feed([PointerEvent(.move, at: p, time: 2), PointerEvent(.leftDown, at: p, time: 2.0005), PointerEvent(.leftUp, at: p, time: 2.001)])
        #expect(run.touch.feed == .finger)
        run.feed([PointerEvent(.move, at: p, time: 3), e(.move, 320, 400, 3.02)])
        run.feed([e(.move, 320, 400, 4), e(.leftDown, 320, 400, 4.0005), e(.leftUp, 320, 400, 4.001)])
        #expect(run.touch.feed == .cursor)
        #expect(run.touch.advice?.contains("绝对鼠标") == true)
        // 又从手指落点开始：回到绝对鼠标，提醒收起
        run.feed([e(.move, 600, 800, 5)])
        #expect(run.touch.feed == .finger)
        #expect(run.touch.advice == nil)
    }

    @Test("隔太久（10 秒以上，本机的鼠标可能动过光标）、一下没结束的，开头不拿来判模式")
    func feedIgnoresLongGaps() {
        var run = Run()
        run.feed([e(.move, 100, 100, 0), e(.move, 600, 800, 11)])
        #expect(run.touch.feed == .unknown)
    }

    @Test("相对鼠标：移动原样放行，滑动不合成；点按、长按照样交翻译器")
    func cursorFeed() {
        var run = Run()
        let p = CGPoint(x: 300, y: 400)
        // 第一下没有上一个事件可比，之后三下都在光标处
        for t in [1.0, 2, 3, 4] { run.feed([PointerEvent(.move, at: p, time: t), PointerEvent(.leftDown, at: p, time: t + 0.0005), PointerEvent(.leftUp, at: p, time: t + 0.001)]) }
        #expect(run.touch.feed == .cursor)
        run.inputs = []
        run.feed([PointerEvent(.move, at: p, time: 5), e(.move, 340, 400, 5.02), e(.move, 380, 400, 5.04)])
        #expect(run.inputs.isEmpty)
    }

    // MARK: 单指滑（绝对鼠标）

    @Test("单指滑：第一个移动补出按下和「认出滑动」，之后每个移动是拖动；停 0.3 秒补抬起，记在最后一个移动的时刻（翻译器按松手前的速度带惯性）")
    func slide() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 420, 1.016), e(.move, 300, 450, 1.032)])
        #expect(run.kinds.suffix(5) == [.release, .press, .recognized(.slide), .drag, .drag])
        #expect(run.inputs.suffix(4).first?.location == CGPoint(x: 300, y: 400))
        #expect(run.touch.deadline == 1.032 + CrossDeskTouch.slideEnd)
        run.advance(to: 2)
        #expect(run.inputs.last == TouchInput(.release, at: CGPoint(x: 300, y: 450), time: 1.032))
        #expect(run.touch.deadline == nil)
    }

    @Test("一个孤立的移动（点按前、双指点前那个）不合成滑动；停太久的两个移动也不连成一下")
    func loneMove() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.inputs = []
        run.feed([e(.move, 300, 420, 1.5)])
        #expect(run.inputs.isEmpty)
    }

    @Test("滑动中手指落到别处（隔 0.15 秒以上、跳出 80 点）：上一下收尾（记在此刻，不甩），新的一下从落点开始")
    func landingStartsNewSlide() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 420, 1.016), e(.move, 300, 600, 1.2), e(.move, 300, 580, 1.216)])
        #expect(run.kinds.suffix(7) == [.press, .recognized(.slide), .drag, .release, .press, .recognized(.slide), .drag])
        #expect(run.inputs.first { $0.kind == .release && $0.time > 1.1 }?.time == 1.2)
        #expect(run.inputs.last { $0.kind == .press }?.location == CGPoint(x: 300, y: 600))
    }

    @Test("网络成团：隔 77ms 跳了 85 点仍是同一下（不到 0.15 秒不算落到别处）")
    func batchedJumpStaysInSlide() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 420, 1.016), e(.move, 300, 505, 1.093), e(.move, 300, 520, 1.1)])
        #expect(run.kinds.filter { $0 == .press }.count == 2)   // 预热的点一下 + 这一下
        #expect(!run.kinds.dropFirst(3).contains(.release))
    }

    @Test("滑动后很快点一下：停了一下的那个移动先扣着，紧跟着同一点的左键按下，它就是点按的移动：内容不跟着动，滑动在点按之前收尾")
    func tapRightAfterSlide() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 420, 1.016), e(.move, 300, 440, 1.032),
                  e(.move, 310, 470, 1.2), e(.leftDown, 310, 470, 1.2005), e(.leftUp, 310, 470, 1.201)])
        let tail = Array(run.inputs.drop { $0.time < 1.1 })
        // 扣着的那个移动只交了一个原地不动的拖动（吞掉原事件），没有挪到 (310,470) 的拖动
        #expect(tail.map(\.kind) == [.drag, .release, .press, .release])
        #expect(tail[0].location == CGPoint(x: 300, y: 440))
        #expect(tail[1] == TouchInput(.release, at: CGPoint(x: 300, y: 440), time: 1.2005))
    }

    @Test("滑动中停了一下又接着滑：扣着的移动在下一个移动前补上；后面什么都没来，到点（20ms）也补上")
    func pauseThenContinue() {
        var next = Run()
        next.feed(fingerWarmUp())
        next.feed([e(.move, 300, 420, 1.016), e(.move, 300, 430, 1.1), e(.move, 300, 440, 1.11)])
        #expect(next.inputs.suffix(3).map(\.location) == [CGPoint(x: 300, y: 420), CGPoint(x: 300, y: 430), CGPoint(x: 300, y: 440)])
        #expect(next.inputs.suffix(3).allSatisfy { $0.kind == .drag })

        var quiet = Run()
        quiet.feed(fingerWarmUp())
        quiet.feed([e(.move, 300, 420, 1.016), e(.move, 300, 430, 1.1)])
        quiet.advance(to: 1.13)
        #expect(quiet.inputs.last == TouchInput(.drag, at: CGPoint(x: 300, y: 430), time: 1.1))
    }

    @Test("滑动中来了左键按下（长按）：滑动收尾记在此刻，再交这一按")
    func pressInterruptsSlide() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 420, 1.016), e(.move, 300, 440, 1.03), e(.move, 300, 450, 1.04), e(.leftDown, 300, 450, 1.0405)])
        #expect(run.inputs.suffix(2).map(\.kind) == [.release, .press])
        #expect(run.inputs.suffix(2).first?.time == 1.0405)
    }

    @Test("抬起丢了（监听被系统停用过）、又来了不按键的移动：这一按作罢，不卡住之后的手势")
    func lostLeftUp() {
        var run = Run()
        run.feed(fingerWarmUp())
        run.feed([e(.move, 300, 400, 2), e(.leftDown, 300, 400, 2.0005), e(.move, 600, 800, 3), e(.move, 600, 830, 3.02)])
        #expect(run.kinds.suffix(3) == [.press, .recognized(.slide), .drag])
    }

    // MARK: 真机录制回放

    @Test("回放绝对鼠标录制：13 次点击；2 次长按松手、2 次长按后小幅挪动（不出防抖）是右键；1 次长按拖是选择；认出绝对鼠标后的 14 下滑动都成了滚动")
    func replayAbsolute() throws {
        var replay = CrossDeskReplay()
        replay.run(try CrossDeskRecording.events("absolute"))
        #expect(replay.clicks == 13)
        #expect(replay.rightClicks == 4)
        #expect(replay.selections == 1)
        #expect(replay.slides == 14)
        #expect(replay.flings > 0)
    }

    @Test("回放相对鼠标录制：认出相对鼠标；移动全部放行（光标照走），不合成滑动；10 次点击、3 次长按拖是选择")
    func replayRelative() throws {
        var replay = CrossDeskReplay()
        replay.run(try CrossDeskRecording.events("relative"))
        #expect(replay.slides == 0)
        #expect(replay.swallowedMoves == 0)
        #expect(replay.clicks == 10)
        #expect(replay.selections == 3)
        var run = Run()
        run.feed(try CrossDeskRecording.events("relative"))
        #expect(run.touch.feed == .cursor)
    }

    @Test("回放绝对鼠标录制、在点过两次的地方放一个关闭按钮：两次都交给 Snug 先归位再关，不补发点击")
    func replayCloseButton() throws {
        var replay = CrossDeskReplay()
        replay.regions = [TouchRegion(frame: CrossDeskReplay.everywhere.frame, scale: 2,
                                      closeButton: CloseButton(frame: CGRect(x: 733, y: -550, width: 20, height: 20), window: 7, windowFrame: .zero))]
        replay.run(try CrossDeskRecording.events("absolute"))
        #expect(replay.closes == 2)
        #expect(replay.clicks == 11)
    }

    @Test("两份录制整理出的输入都合标准语法")
    func recordingsAreGrammatical() throws {
        for name in ["absolute", "relative"] {
            var run = Run()
            run.feed(try CrossDeskRecording.events(name))
            run.advance(to: .infinity)
            var grammar = TouchGrammar()
            let problems = run.inputs.compactMap { grammar.check($0) }
            #expect(problems.isEmpty, "\(name)：\(problems.prefix(3))")
        }
    }
}
