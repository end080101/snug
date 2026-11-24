// CrossDesk 的手势整理：把它注入的鼠标事件整理成标准手指输入，交给 Snug 共用的翻译器（滚动带惯性、长按选择、长按松手右键、关闭按钮）。
// CrossDesk 的线上只有鼠标，手机端的手势先在手机上认好再发（iOS 1.7.6，RemoteTouchInputView.swift）：
// - 点一下：在手指处发移动、左键按下、抬起，同一时刻发出（真机 13/13 在 2ms 内到齐）
// - 长按 0.35 秒：在手指处发移动、左键按下；之后拖动（按着左键的移动），松手发抬起
// - 单指滑：「绝对鼠标」下只发不按键的移动，坐标就是手指位置，开始和结束都没有信号；
//   「相对鼠标」（默认）下只发光标位移，拿不到手指位置，翻译不了
// - 虚拟鼠标键：在光标处发左键按下、抬起，前面不带移动
// 所以这里：不按键的移动合成手指的按下、拖动，停 slideEnd 没有新移动、或手指落到别处就补抬起；
// 左键按下后没有很快抬起的是长按，告诉翻译器「已认出长按」；虚拟鼠标键原样放行。
// 「绝对鼠标」还是「相对鼠标」看每一下开头落在哪：相对鼠标每一下都从光标停的地方开始，绝对鼠标从手指落点开始
import Foundation
import SnugCore

package struct CrossDeskTouch: TouchNormalizer {
    /// 手机端在发什么
    package enum Feed: Equatable, Sendable {
        /// 还看不出（刚开监听）：不合成滑动
        case unknown
        /// 绝对鼠标：手指位置
        case finger
        /// 相对鼠标：光标位移，翻译不了滑动
        case cursor
    }

    /// iOS 客户端按住 0.35 秒才认长按（heldDrag.minimumPressDuration）：左键按下到达时，手指已经按了这么久
    static let clientHoldDelay: TimeInterval = 0.35
    /// 左键按下后这么久还没抬起就是长按：Snug 按住 0.5 秒算长按，减掉客户端已经等的
    static let holdAfterDown = TouchTranslator.holdDuration - clientHoldDelay
    /// 点按、长按的那个移动和左键按下同一时刻发出：按下前这么久内、同一位置有移动才是手指，否则是虚拟鼠标键
    static let touchMoveLead: TimeInterval = 0.02
    /// 单指滑停这么久没有新的移动，算松手（真机：滑动中停顿最长 0.275 秒，下一下最快隔 0.296 秒）
    static let slideEnd: TimeInterval = 0.3
    /// 隔开至少这么久、又跳出这么远的移动，是手指抬起后落到了别处：抬手再落下、再挪出客户端的防抖，比这快不了。
    /// 网络成团时滑动中也会隔 60–100ms 跳一大步（真机最大 85 点）；隔 0.15 秒以上的单步最大 73 点
    static let landingGap: TimeInterval = 0.15
    static let landingJump = 80.0
    /// 滑动中停了这么久以后的那个移动先扣一下（最多 touchMoveLead），看是不是点按的移动
    static let pauseGap: TimeInterval = 0.06
    /// 安静这么久之后的第一个移动算一下的开头，拿来判手机端在发什么；隔太久（本机的鼠标可能动过光标）的不算
    static let gestureGap: TimeInterval = 0.25
    static let voteWindow: TimeInterval = 10
    /// 开头和上一个事件在同一点（相对鼠标每一下都从光标停的地方开始）；连续这么多下都这样才认作相对鼠标，中间有一下挪开就重新数。
    /// 绝对鼠标原地再点、按住不动再接着滑也会这样，分不出来：误认了只是一下滑动不滚，下一下手指落到别处就恢复。
    /// 11-23 手机实测中途从绝对鼠标切到相对鼠标时没认出来（原因未查，见上下文文档 6.3）；一开始就是相对鼠标的不受影响（从没认作绝对鼠标，移动照常放行）
    static let samePlace = 0.5
    static let cursorVotes = 3

    package static let consumes: Set<PointerEvent.Kind> = [.move, .leftDown, .leftDrag, .leftUp]

    package private(set) var feed = Feed.unknown

    /// 连续几下开头落在上一个事件的位置上
    private var cursorRun = 0
    /// 这一按：手指的（交翻译器）还是虚拟鼠标键的（原样放行）
    private enum Press { case finger(down: PointerEvent, held: Bool), virtual }
    private var press: Press?
    /// 正在合成的滑动：上一个移动
    private var slide: PointerEvent?
    /// 滑动中停了一下后的那个移动：可能是点按、长按的移动（紧跟着就是同一点的左键按下），先扣着看下一个事件
    private var paused: PointerEvent?
    /// 一个孤立的移动：可能是滑动的头，也可能是点按前那个移动（看下一个事件）
    private var candidate: PointerEvent?
    private var last: PointerEvent?

    package init() {}

    package var deadline: TimeInterval? {
        // 扣着的移动说明手指在 slideEnd 之内又动了：先等它见分晓，滑动的收尾从它算起（不然停 0.28–0.3 秒时收尾先到，抬起记在扣着的移动之前）
        if let paused { return paused.time + Self.touchMoveLead }
        return slide.map { $0.time + Self.slideEnd }
    }

    package mutating func tick(at time: TimeInterval) -> [TouchInput] {
        var inputs: [TouchInput] = []
        if let p = paused, time >= p.time + Self.touchMoveLead {
            paused = nil
            slide = p
            inputs.append(TouchInput(.drag, at: p.location, time: p.time))
        }
        // 停手收尾：抬起记在最后一个移动的时刻，翻译器按松手前的速度带惯性
        if let s = slide, time >= s.time + Self.slideEnd {
            slide = nil
            inputs.append(TouchInput(.release, at: s.location, time: s.time))
        }
        return inputs
    }

    package mutating func normalize(_ event: PointerEvent) -> Normalized {
        defer { last = event }
        var before = settlePaused(by: event)
        vote(event)
        switch event.kind {
        case .move: return move(event, before: before)
        case .leftDown:
            // 被打断的滑动：抬起记在此刻，翻译器算不出速度就不甩（否则惯性马上被这一按停住，这一下点按会被吞成「只是停住」）
            if let s = slide {
                before.append(TouchInput(.release, at: s.location, time: event.time))
                slide = nil
            }
            candidate = nil
            guard let l = last, l.kind == .move, distance(l.location, event.location) <= Self.samePlace,
                  event.time - l.time <= Self.touchMoveLead else {
                press = .virtual
                return Normalized(before: before, current: nil)
            }
            press = .finger(down: event, held: false)
            return Normalized(before: before, current: TouchInput(.press, at: event.location, time: event.time))
        case .leftDrag:
            guard case .finger(let down, let held) = press else { return Normalized(before: before, current: nil) }
            // 左键按下后有拖动：客户端认出了长按（单指滑不按键），之后是选择
            press = .finger(down: down, held: true)
            if !held { before.append(TouchInput(.recognized(.hold), at: event.location, time: event.time)) }
            return Normalized(before: before, current: TouchInput(.drag, at: event.location, time: event.time))
        case .leftUp:
            defer { press = nil }
            guard case .finger(let down, let held) = press else { return Normalized(before: before, current: nil) }
            if !held, event.time - down.time >= Self.holdAfterDown {
                before.append(TouchInput(.recognized(.hold), at: event.location, time: event.time))
            }
            return Normalized(before: before, current: TouchInput(.release, at: event.location, time: event.time))
        }
    }

    private mutating func move(_ event: PointerEvent, before: [TouchInput]) -> Normalized {
        var before = before
        // 按着左键时 CrossDesk 发的是拖动；这时来了不按键的移动，说明抬起丢了（监听被系统停用过）：这一按作罢
        press = nil
        guard feed == .finger else {
            slide = nil
            candidate = nil
            return Normalized(before: before, current: nil)
        }
        if let s = slide {
            if landed(event, after: s) {
                before.append(TouchInput(.release, at: s.location, time: event.time))
                slide = nil
                candidate = event
                return Normalized(before: before, current: nil)
            }
            if event.time - s.time >= Self.pauseGap {
                // 停了一下：先吞掉、内容不动，看下一个事件是不是同一点的左键按下
                paused = event
                return Normalized(before: before, current: TouchInput(.drag, at: s.location, time: event.time))
            }
            slide = event
            return Normalized(before: before, current: TouchInput(.drag, at: event.location, time: event.time))
        }
        if let c = candidate, event.time - c.time < Self.slideEnd, !landed(event, after: c) {
            candidate = nil
            slide = event
            before += [TouchInput(.press, at: c.location, time: c.time), TouchInput(.recognized(.slide), at: c.location, time: c.time)]
            return Normalized(before: before, current: TouchInput(.drag, at: event.location, time: event.time))
        }
        candidate = event
        return Normalized(before: before, current: nil)
    }

    /// 扣着的移动见分晓：紧跟着同一点的左键按下，它是点按、长按的移动，滑动在它之前就结束了（抬起交给按下那一支补）；否则接着滑
    private mutating func settlePaused(by event: PointerEvent) -> [TouchInput] {
        guard let p = paused else { return [] }
        paused = nil
        if event.kind == .leftDown, distance(p.location, event.location) <= Self.samePlace, event.time - p.time <= Self.touchMoveLead {
            return []
        }
        slide = p
        return [TouchInput(.drag, at: p.location, time: p.time)]
    }

    /// 一下的开头落在哪，判手机端在发手指位置还是光标位移
    private mutating func vote(_ event: PointerEvent) {
        guard event.kind == .move, press == nil, slide == nil, let l = last else { return }
        let gap = event.time - l.time
        guard gap >= Self.gestureGap, gap <= Self.voteWindow else { return }
        let d = distance(l.location, event.location)
        if d <= Self.samePlace {
            cursorRun += 1
            if cursorRun >= Self.cursorVotes { feed = .cursor }
        } else {
            cursorRun = 0
            if d >= Self.landingJump { feed = .finger }
        }
    }

    private func landed(_ event: PointerEvent, after previous: PointerEvent) -> Bool {
        event.time - previous.time >= Self.landingGap && distance(event.location, previous.location) >= Self.landingJump
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }
}
