import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

// 黄金母本：远控发「按下 → 拖动 → 抬起」（手指直通）时，手势翻译的全部回应。
// 按固定种子生成几百段手势（点、滑、甩、惯性中点、长按拖、长按松手、关闭按钮、屏外、宽档、成团到达），
// 回应和惯性帧逐条写成文本取摘要。翻译器、管线怎么拆，这份摘要都必须一字不差；
// 只有有意改手感（阈值、惯性）时才更新常量，并在提交里写明改了什么

/// 固定种子的随机数（SplitMix64）：每次跑生成同样的手势
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 生成手势、喂给翻译器、记下每一条回应
private struct GoldenRun {
    static let close = CGRect(x: 8, y: 30, width: 14, height: 14)
    /// 基准宽度的手机屏，带关闭按钮
    static let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1,
                                   closeButton: CloseButton(frame: close, window: 7, windowFrame: CGRect(x: 0, y: 22, width: 540, height: 900)))
    /// 最宽一档：阈值都是 2 倍，关闭按钮跟着放大
    static let widest = TouchRegion(frame: CGRect(x: 3000, y: 0, width: 1080, height: 1900), scale: 2,
                                    closeButton: CloseButton(frame: CGRect(x: 3016, y: 60, width: 28, height: 28), window: 8,
                                                             windowFrame: CGRect(x: 3000, y: 44, width: 1080, height: 1800)))

    var rng: SplitMix64
    var translator = TouchTranslator()
    var lines: [String] = []
    var time = 0.0
    /// 这一按所在的范围：之后的拖动、抬起跟着这一下走（和系统层一样）
    var pressed: TouchRegion?
    var counts: [String: Int] = [:]

    init(seed: UInt64) { rng = SplitMix64(state: seed) }

    mutating func random(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
    mutating func random(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }

    /// 惯性按 60fps 走到 until 为止（系统层的计时器就是这样喂的）
    mutating func coast(until: TimeInterval) {
        while translator.isCoasting, time + 1 / Momentum.frameRate <= until {
            time += 1 / Momentum.frameRate
            if let step = translator.momentumFrame() { record("帧", describe(step)) }
        }
        time = max(time, until)
    }

    mutating func send(_ kind: TouchInput.Kind, _ point: CGPoint, at t: TimeInterval) {
        coast(until: t)
        if kind == .press { pressed = [Self.phone, Self.widest].first { $0.frame.contains(point) } }
        let response = translator.handle(TouchInput(kind, at: point, time: t), in: pressed)
        record("\(kind) \(fmt(point.x)),\(fmt(point.y)) @\(fmt(t))", describe(response))
    }

    mutating func record(_ input: String, _ output: String) {
        lines.append("\(input) → \(output)")
    }

    // MARK: 手势

    /// 范围里随便一点（宽档的屏在右边）；偶尔落在屏外
    mutating func spot() -> (CGPoint, Double) {
        switch random(0...9) {
        case 0: return (CGPoint(x: random(-900.0 ... -100), y: random(0.0...900)), 1)
        case 1...3: return (CGPoint(x: random(3100.0...3980), y: random(100.0...1800)), 2)
        default: return (CGPoint(x: random(40.0...500), y: random(60.0...900)), 1)
        }
    }

    mutating func gesture() {
        let gap = random(0...4) == 0 ? random(0.02...0.3) : random(0.3...1.5)
        var t = time + gap
        var (p, scale) = spot()
        if random(0...3) == 0 { p = scale == 2 ? CGPoint(x: 3030, y: 74) : CGPoint(x: 15, y: 37) }   // 关闭按钮
        send(.press, p, at: t)
        switch random(0...6) {
        case 0, 1:
            // 点：防抖内抖一下再抬起
            if random(0...1) == 0 {
                t += random(0.01...0.15)
                send(.drag, CGPoint(x: p.x + random(-3.0...3) * scale, y: p.y + random(-3.0...3) * scale), at: t)
            }
            t += random(0.02...0.4)
            send(.release, p, at: t)
        case 2, 3:
            // 滑或甩：每帧 8–20ms，偶尔几个挤在同一时刻到（远控成团转发），末尾有时停住再松手
            let angle = random(0.0...(2 * .pi)), speed = random(80.0...3000) * scale
            var q = p
            for _ in 0..<random(3...40) {
                let dt = random(0...5) == 0 ? 0 : random(0.008...0.02)
                t += dt
                q = CGPoint(x: q.x + cos(angle) * speed * max(dt, 0.004), y: q.y + sin(angle) * speed * max(dt, 0.004))
                send(.drag, q, at: t)
            }
            if random(0...3) == 0 { t += random(0.1...0.3) }
            t += random(0.0...0.02)
            send(.release, q, at: t)
        case 4:
            // 长按松手：可能小抖几下
            for _ in 0..<random(0...3) {
                t += random(0.05...0.2)
                send(.drag, CGPoint(x: p.x + random(-4.0...4) * scale, y: p.y + random(-4.0...4) * scale), at: t)
            }
            t = max(t, time) + random(0.3...1.4)
            send(.release, p, at: t)
        default:
            // 长按后拖（选择）或按住不久就拖（滚动）：分水岭在 0.5 秒附近
            t += random(0.2...1.2)
            var q = p
            for _ in 0..<random(2...25) {
                t += random(0.01...0.05)
                q = CGPoint(x: q.x + random(-6.0...12) * scale, y: q.y + random(-6.0...12) * scale)
                send(.drag, q, at: t)
            }
            t += random(0.01...0.1)
            send(.release, q, at: t)
        }
    }

    // MARK: 文本

    mutating func describe(_ r: TouchResponse) -> String {
        if !r.passOriginal { counts["吞", default: 0] += 1 }
        return (r.passOriginal ? "放行" : "吞") + (r.commands.isEmpty ? "" : " " + r.commands.map { describe($0) }.joined(separator: " | "))
    }

    mutating func describe(_ c: TouchCommand) -> String {
        switch c {
        case .replayPress: counts["补按下", default: 0] += 1; return "补按下"
        case .replayCurrent: counts["补当前", default: 0] += 1; return "补当前"
        case .rightClick(let p): counts["右键", default: 0] += 1; return "右键 \(fmt(p.x)),\(fmt(p.y))"
        case .closeWindow(let p): counts["关窗", default: 0] += 1; return "关窗 \(fmt(p.x)),\(fmt(p.y))"
        case .scroll(let s): return describe(s)
        }
    }

    mutating func describe(_ s: ScrollStep) -> String {
        counts[s.momentum == .none ? "滚动" : "惯性", default: 0] += 1
        return "滚 \(s.pixelsX),\(s.pixelsY) Δ\(fmt(s.deltaX)),\(fmt(s.deltaY)) 相\(s.phase.rawValue) 惯\(s.momentum.rawValue) @\(fmt(s.location.x)),\(fmt(s.location.y))"
    }

    func fmt(_ v: Double) -> String { String(format: "%.4f", v) }
    func fmt(_ v: CGFloat) -> String { fmt(Double(v)) }
}

/// FNV-1a 64：不依赖 CryptoKit，跨次运行稳定
private func digest(_ text: String) -> UInt64 {
    text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
}

private func goldenRun() -> GoldenRun {
    var run = GoldenRun(seed: 20261123)
    for _ in 0..<320 { run.gesture() }
    run.coast(until: run.time + 3)
    return run
}

@Suite("手势翻译的黄金母本")
struct TouchGoldenMasterTests {
    /// 改了手感才更新：先确认 counts 的变化符合预期，再换这两个常量
    static let expectedDigest: UInt64 = 0x74BE_2D96_F2B4_1826
    static let expectedCounts = ["补按下": 116, "补当前": 116, "右键": 49, "关窗": 17, "滚动": 2215, "惯性": 3051, "吞": 2864]

    @Test("手指直通的全部回应和惯性帧，与母本逐字一致")
    func fingerTranscriptUnchanged() {
        let run = goldenRun()
        let text = run.lines.joined(separator: "\n")
        #expect(run.counts == Self.expectedCounts, "回应的构成变了：\(run.counts.sorted { $0.key < $1.key })")
        #expect(digest(text) == Self.expectedDigest, "摘要变了：0x\(String(digest(text), radix: 16, uppercase: true))，共 \(run.lines.count) 条")
    }

    @Test("母本覆盖到了每一种回应：点击、滚动、惯性、惯性中点按只停住、右键、关闭按钮、屏外放行")
    func coversEveryResponse() {
        let run = goldenRun()
        for kind in ["补按下", "补当前", "右键", "关窗", "滚动", "惯性"] { #expect(run.counts[kind, default: 0] > 10, "\(kind) 太少") }
        #expect(run.lines.contains { $0.hasPrefix("press") && $0.hasSuffix("→ 放行") }, "没有屏外按下")
        #expect(run.lines.contains { $0.hasPrefix("press") && $0.contains("惯3") }, "没有惯性中按下")
    }
}
