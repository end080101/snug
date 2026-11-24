import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let p0 = CGPoint(x: 100, y: 300)
/// 基准宽度的手机屏；elsewhere 是别处的手机屏，用来表示「在手机屏外按下」
private let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1)
private let elsewhere = TouchRegion(frame: CGRect(x: 2000, y: 0, width: 540, height: 950), scale: 1)
/// 最宽一档（1080）的手机屏：阈值都是基准的 2 倍
private let widest = TouchRegion(frame: CGRect(x: 0, y: 0, width: 1080, height: 1900), scale: 2)

private func input(_ kind: TouchInput.Kind, _ x: Double, _ y: Double, _ t: Double) -> TouchInput {
    TouchInput(kind, at: CGPoint(x: x, y: y), time: t)
}

private func scrolls(_ r: TouchResponse) -> [ScrollStep] {
    r.commands.compactMap { if case .scroll(let s) = $0 { s } else { nil } }
}

@Suite("手势翻译 TouchTranslator")
struct TouchTranslatorTests {
    @Test("参数和 iOS 一致：防抖 10 点，按住 0.5 秒算长按")
    func constants() {
        #expect(TouchTranslator.slop == 10)
        #expect(TouchTranslator.holdDuration == 0.5)
    }

    @Test("手机屏外按下：原样放行，之后的拖动、抬起也放行（原来的屏保持远控原本的手势）")
    func outsidePassesThrough() {
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 100, 300, 0), in: elsewhere) == .pass)
        #expect(t.handle(input(.drag, 160, 300, 0.1), in: elsewhere) == .pass)
        #expect(t.handle(input(.release, 160, 300, 0.2), in: elsewhere) == .pass)
    }

    @Test("点一下：按下先扣住，抬起时补发按下和抬起")
    func tap() {
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 100, 300, 0), in: phone) == TouchResponse(passOriginal: false, commands: []))
        // 防抖范围内的小抖动不算滑
        #expect(t.handle(input(.drag, 104, 305, 0.05), in: phone) == TouchResponse(passOriginal: false, commands: []))
        #expect(t.handle(input(.release, 104, 305, 0.1), in: phone)
                == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))
    }

    @Test("点窗口自己的关闭按钮：不补发点击，交给 Snug 先放回原位再关；按住、滑动照旧")
    func tapCloseButton() {
        var region = phone
        region.closeButton = CloseButton(frame: CGRect(x: 8, y: 30, width: 14, height: 14), window: 7, windowFrame: CGRect(x: 0, y: 22, width: 540, height: 900))
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 15, 37, 0), in: region) == TouchResponse(passOriginal: false, commands: []))
        #expect(t.handle(input(.release, 16, 38, 0.1), in: region)
                == TouchResponse(passOriginal: false, commands: [.closeWindow(at: CGPoint(x: 15, y: 37))]))
        // 按住还是右键菜单，滑走还是滚动：只拦「点一下」
        _ = t.handle(input(.press, 15, 37, 1), in: region)
        #expect(t.handle(input(.release, 15, 37, 1.6), in: region).commands == [.rightClick(at: CGPoint(x: 15, y: 37))])
        _ = t.handle(input(.press, 15, 37, 2), in: region)
        #expect(scrolls(t.handle(input(.drag, 15, 80, 2.05), in: region)).map(\.phase) == [.began, .changed])
        // 按钮外点一下照常
        _ = t.handle(input(.release, 15, 80, 2.1), in: region)
        _ = t.handle(input(.press, 100, 300, 3), in: region)
        #expect(t.handle(input(.release, 100, 300, 3.1), in: region).commands == [.replayPress, .replayCurrent])
    }

    @Test("关闭按钮点下去时再核对：这一点最上面的还是那个窗口、还在原来的位置才算；被拖走、被盖住、进了全屏都不算；指针自己不算遮挡")
    func closeButtonVerified() {
        let window = CGRect(x: 0, y: 22, width: 540, height: 900)
        let button = CloseButton(frame: CGRect(x: 8, y: 30, width: 14, height: 14), window: 7, windowFrame: window)
        let tap = CGPoint(x: 15, y: 37)
        typealias Shown = [(id: UInt32, frame: CGRect, level: Int)]
        let onTop: Shown = [(7, window, 0), (3, CGRect(x: -800, y: 0, width: 2000, height: 2000), 0)]
        let rounded: Shown = [(7, CGRect(x: 1, y: 22, width: 540, height: 901), 0)]   // 取整差一点
        let covered: Shown = [(9, CGRect(x: 0, y: 22, width: 540, height: 892), 3), (7, window, 0)]   // 被别的窗口盖住（浮动面板）
        let dragged: Shown = [(7, CGRect(x: 0, y: 200, width: 540, height: 900), 0)]   // 被拖走了，那里是桌面
        let fullScreen: Shown = [(7, CGRect(x: 0, y: 0, width: 540, height: 950), 0)]   // 进了全屏
        // 指针在窗口服务器里也是个窗口（最高一层），远控点下去前把它挪到了这一点（CrossDesk 点按前先发移动，11-23 实测）
        let pointer: Shown = [(2, CGRect(x: 10, y: 32, width: 28, height: 40), CloseButton.pointerLevel), (7, window, 0)]
        #expect(button.isFrontmost(at: tap, onScreen: onTop))
        #expect(button.isFrontmost(at: tap, onScreen: pointer))
        #expect(button.isFrontmost(at: CGPoint(x: 15, y: 37.5), onScreen: rounded))
        #expect(!button.isFrontmost(at: tap, onScreen: covered))
        #expect(!button.isFrontmost(at: tap, onScreen: dragged))
        #expect(!button.isFrontmost(at: tap, onScreen: fullScreen))
        #expect(!button.isFrontmost(at: CGPoint(x: 100, y: 300), onScreen: onTop))   // 不在按钮上
    }

    @Test("快速滑动：开始滚动（began 再 changed），手指往下拖内容往下走，抬起发 ended")
    func swipeScrolls() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        let first = t.handle(input(.drag, 100, 320, 0.05), in: phone)
        #expect(first.passOriginal == false)
        let s = scrolls(first)
        #expect(s.map(\.phase) == [.began, .changed])
        #expect(s[1].pixelsY == 20)
        #expect(s[1].deltaY == 20)
        #expect(s.allSatisfy { $0.location == p0 })   // 滚的是按下处的那个列表

        let next = scrolls(t.handle(input(.drag, 100, 310, 0.06), in: phone))
        #expect(next.map(\.phase) == [.changed])
        #expect(next[0].pixelsY == -10)

        let end = t.handle(input(.release, 100, 310, 0.5), in: phone)
        #expect(scrolls(end).map(\.phase) == [.ended])
        #expect(!t.isCoasting)   // 停了一会儿才松手：不带惯性
    }

    @Test("滑出手机屏也跟着这一下走")
    func gestureContinuesOutside() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        _ = t.handle(input(.drag, 100, 340, 0.05), in: elsewhere)
        #expect(t.handle(input(.drag, 100, 380, 0.06), in: elsewhere).passOriginal == false)
    }

    @Test("慢慢拖的小数位移累计成整数像素，不会一直是 0")
    func fractionalAccumulates() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        _ = t.handle(input(.drag, 100, 311, 0.01), in: phone)
        var total: Int32 = 0
        for i in 1...4 {
            total += scrolls(t.handle(input(.drag, 100, 311 + 0.5 * Double(i), 0.01 + 0.01 * Double(i)), in: phone))[0].pixelsY
        }
        #expect(total == 2)
    }

    @Test("按住 0.5 秒再拖：补发按下和当前拖动，之后的拖动和抬起原样放行（照旧选择）")
    func holdThenDragSelects() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        #expect(t.handle(input(.drag, 130, 300, 0.6), in: phone)
                == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))
        #expect(t.handle(input(.drag, 160, 300, 0.7), in: phone) == .pass)
        #expect(t.handle(input(.release, 160, 300, 0.8), in: phone) == .pass)
    }

    @Test("按住 0.5 秒不动再松手：在按下的地方点右键")
    func longPressRightClicks() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        #expect(t.handle(input(.release, 102, 301, 0.7), in: phone)
                == TouchResponse(passOriginal: false, commands: [.rightClick(at: p0)]))
    }

    @Test("差一点 0.5 秒松手仍是点击")
    func shortHoldIsTap() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        #expect(t.handle(input(.release, 100, 300, 0.49), in: phone).commands == [.replayPress, .replayCurrent])
    }

    @Test("甩一下：松手后带惯性，速度逐帧衰减，最后发惯性结束")
    func flingCoasts() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), in: phone) }
        _ = t.handle(input(.release, 100, 400, 0.1), in: phone)
        #expect(t.isCoasting)
        var frames: [ScrollStep] = []
        while let f = t.momentumFrame() { frames.append(f) }
        #expect(!t.isCoasting)
        #expect(frames.first?.momentum == .begin)
        #expect(frames.last?.momentum == .end)
        #expect(frames.dropFirst().dropLast().allSatisfy { $0.momentum == .continue })
        #expect(frames.allSatisfy { $0.phase == .none })
        let deltas = frames.dropLast().map(\.deltaY)
        #expect(zip(deltas, deltas.dropFirst()).allSatisfy { $0 > $1 })   // 越来越慢
        #expect(deltas.first! > 0)                                        // 往下甩，接着往下走
        #expect(frames.count < 70)                                        // 一秒多一点就停
    }

    @Test("惯性中再按下：先发惯性结束，再扣住这次按下")
    func pressStopsMomentum() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), in: phone) }
        _ = t.handle(input(.release, 100, 400, 0.1), in: phone)
        _ = t.momentumFrame()
        let r = t.handle(input(.press, 100, 300, 0.2), in: phone)
        #expect(r.passOriginal == false)
        #expect(scrolls(r).map(\.momentum) == [.end])
        #expect(!t.isCoasting)
    }

    @Test("惯性中点一下：只是停住，不补发点击（不点到还在滚的内容）")
    func tapStopsCoastWithoutClick() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), in: phone) }
        _ = t.handle(input(.release, 100, 400, 0.1), in: phone)
        _ = t.momentumFrame()
        _ = t.handle(input(.press, 100, 300, 0.2), in: phone)
        let r = t.handle(input(.release, 100, 300, 0.3), in: phone)
        #expect(r.passOriginal == false)
        #expect(r.commands.isEmpty)
        // 下一次普通的点照常点击
        _ = t.handle(input(.press, 100, 300, 1.0), in: phone)
        #expect(t.handle(input(.release, 100, 300, 1.1), in: phone).commands == [.replayPress, .replayCurrent])
    }

    @Test("事件扎堆到达（网络抖了一下）：慢慢拖不会甩出几屏，速度按更长的跨度算、并且封顶")
    func bunchedEventsDoNotOverFling() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        // 每 50ms 拖 5 点，很慢
        for i in 1...4 { _ = t.handle(input(.drag, 100, 300 + 5 * Double(i), 0.05 * Double(i)), in: phone) }
        // 停了 120ms，3 个拖动挤在 3ms 里一起到，随即松手
        for i in 1...3 { _ = t.handle(input(.drag, 100, 320 + 5 * Double(i), 0.32 + 0.001 * Double(i)), in: phone) }
        _ = t.handle(input(.release, 100, 335, 0.324), in: phone)
        var total = 0.0
        while let f = t.momentumFrame() { total += f.deltaY }
        #expect(total < 200)
    }

    @Test("甩得再快，惯性速度也有上限")
    func flingSpeedCapped() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 0, 0), in: phone)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 200 * Double(i), 0.02 * Double(i)), in: phone) }
        _ = t.handle(input(.release, 100, 1000, 0.1), in: phone)
        let first = t.momentumFrame()
        let cap = TouchTranslator.maxFlingSpeed / Momentum.frameRate
        #expect((first?.deltaY ?? 0) <= cap + 1)
    }

    @Test("宽档下防抖按比例放大：1080 那一档里手指挪 15 点仍算点一下（基准宽度下就成了滚动）")
    func slopScalesWithScreen() {
        var wide = TouchTranslator()
        _ = wide.handle(input(.press, 100, 300, 0), in: widest)
        #expect(wide.handle(input(.drag, 115, 300, 0.05), in: widest) == TouchResponse(passOriginal: false, commands: []))
        #expect(wide.handle(input(.release, 115, 300, 0.1), in: widest)
            == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))

        var base = TouchTranslator()
        _ = base.handle(input(.press, 100, 300, 0), in: phone)
        #expect(!scrolls(base.handle(input(.drag, 115, 300, 0.05), in: phone)).isEmpty)
    }

    @Test("宽档下惯性门槛按比例放大：350 点/秒在基准宽度下带惯性，在 1080 那一档（门槛 400）不带")
    func flingScalesWithScreen() {
        for (screen, coasts) in [(phone, true), (widest, false)] {
            var t = TouchTranslator()
            _ = t.handle(input(.press, 100, 300, 0), in: screen)
            _ = t.handle(input(.drag, 100, 320, 0.05), in: screen)
            _ = t.handle(input(.drag, 100, 335, 0.1), in: screen)
            _ = t.handle(input(.release, 100, 335, 0.1), in: screen)
            #expect(t.isCoasting == coasts)
        }
    }

    // MARK: 远控已认出的手势（各家整理交来 recognized）

    @Test("认出长按：按下才 0.05 秒拖出防抖也是选择（补发按下和当前拖动，之后放行）；防抖内的小抖动照旧扣着")
    func recognizedHoldSelects() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        #expect(t.handle(input(.recognized(.hold), 100, 300, 0.01), in: phone) == TouchResponse(passOriginal: false, commands: []))
        #expect(t.handle(input(.drag, 104, 303, 0.03), in: phone) == TouchResponse(passOriginal: false, commands: []))
        #expect(t.handle(input(.drag, 100, 330, 0.05), in: phone)
                == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))
        #expect(t.handle(input(.drag, 100, 360, 0.08), in: phone) == .pass)
        #expect(t.handle(input(.release, 100, 360, 0.1), in: phone) == .pass)
        #expect(!t.isCoasting)
    }

    @Test("认出长按：按下才 0.1 秒没拖就松手也是右键；按在关闭按钮上同样是右键（和按住 0.5 秒一样）")
    func recognizedHoldRightClicks() {
        var region = phone
        region.closeButton = CloseButton(frame: CGRect(x: 8, y: 30, width: 14, height: 14), window: 7, windowFrame: CGRect(x: 0, y: 22, width: 540, height: 900))
        for p in [CGPoint(x: 100, y: 300), CGPoint(x: 15, y: 37)] {
            var t = TouchTranslator()
            _ = t.handle(TouchInput(.press, at: p, time: 0), in: region)
            _ = t.handle(TouchInput(.recognized(.hold), at: p, time: 0.05), in: region)
            #expect(t.handle(TouchInput(.release, at: p, time: 0.1), in: region).commands == [.rightClick(at: p)])
        }
    }

    @Test("认出滑动：补出来的按下马上开始滚动（began），之后每次拖动都滚，慢也不会变成选择；松手 ended，甩得快带惯性；从不补发点击")
    func recognizedSlideScrolls() {
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 100, 300, 0), in: phone) == TouchResponse(passOriginal: false, commands: []))
        #expect(scrolls(t.handle(input(.recognized(.slide), 100, 300, 0), in: phone)).map(\.phase) == [.began])
        // 很慢：0.8 秒才挪 3 点，照样是滚动
        let slow = t.handle(input(.drag, 100, 303, 0.8), in: phone)
        #expect(!slow.passOriginal && scrolls(slow).map(\.pixelsY) == [3])
        for (i, y) in [340.0, 380, 420].enumerated() { _ = t.handle(input(.drag, 100, y, 0.81 + Double(i) * 0.016), in: phone) }
        let end = t.handle(input(.release, 100, 420, 0.85), in: phone)
        #expect(scrolls(end).map(\.phase) == [.ended])
        #expect(t.isCoasting)

        // 没挪动就收尾：只有 began、ended，不点到任何东西
        var still = TouchTranslator()
        _ = still.handle(input(.press, 100, 300, 0), in: phone)
        _ = still.handle(input(.recognized(.slide), 100, 300, 0), in: phone)
        let quiet = still.handle(input(.release, 100, 300, 0.3), in: phone)
        #expect(quiet.commands.allSatisfy { if case .scroll = $0 { true } else { false } })
        #expect(!still.isCoasting)
    }

    @Test("认出的手势只管还没判出来的那一按：屏外按下的原样放行；手指已经滚起来、长按已经在选，都不改")
    func recognizedOnlyWhilePending() {
        var outside = TouchTranslator()
        _ = outside.handle(input(.press, 100, 300, 0), in: elsewhere)
        #expect(outside.handle(input(.recognized(.slide), 100, 300, 0), in: elsewhere) == .pass)
        #expect(outside.handle(input(.drag, 100, 360, 0.05), in: elsewhere) == .pass)

        var scrolling = TouchTranslator()
        _ = scrolling.handle(input(.press, 100, 300, 0), in: phone)
        _ = scrolling.handle(input(.drag, 100, 340, 0.05), in: phone)
        #expect(scrolling.handle(input(.recognized(.hold), 100, 340, 0.06), in: phone) == .pass)
        #expect(scrolls(scrolling.handle(input(.drag, 100, 380, 0.07), in: phone)).map(\.phase) == [.changed])
    }

    @Test("惯性中补出一次滑动：先停掉惯性，再开始新的滚动")
    func recognizedSlideStopsMomentum() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), in: phone)
        for (i, y) in [340.0, 400, 460].enumerated() { _ = t.handle(input(.drag, 100, y, 0.016 * Double(i + 1)), in: phone) }
        _ = t.handle(input(.release, 100, 460, 0.05), in: phone)
        #expect(t.isCoasting)
        let press = t.handle(input(.press, 200, 500, 0.2), in: phone)
        #expect(scrolls(press).map(\.momentum) == [.end])
        #expect(scrolls(t.handle(input(.recognized(.slide), 200, 500, 0.2), in: phone)).map(\.phase) == [.began])
        #expect(!t.isCoasting)
    }
}
