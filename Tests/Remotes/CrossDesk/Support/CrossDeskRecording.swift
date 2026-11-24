import CoreGraphics
import Foundation
import RemoteCrossDesk
import SnugCore

/// 真机录制的夹具：主人的 iPhone（App Store 版 CrossDesk）连 Mac 实体屏，2026-11-23，
/// 用 docs/remote-adapter/crossdesk/recordings/crossdesk_events.swift 只听不改地记下带 CROSSDES 记号的鼠标事件。
/// 一行一个事件：「秒 种类 (x,y) … [ts=CGEvent 时间戳纳秒]」；relative 那份没有 ts，用秒（毫秒精度）
enum CrossDeskRecording {
    /// 只取整理要看的四种（不按键的移动、左键三种）；右键、滚轮不经过手势层
    static func events(_ name: String) throws -> [PointerEvent] {
        guard let url = Bundle.module.url(forResource: "ios-1.7.6-\(name)", withExtension: "log", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let kinds: [Substring: PointerEvent.Kind] = ["move": .move, "Ldown": .leftDown, "Ldrag": .leftDrag, "Lup": .leftUp]
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count >= 3, let seconds = Double(fields[0]), let kind = kinds[fields[1]] else { return nil }
            let xy = fields[2].dropFirst().dropLast().split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return nil }
            let ts = fields.last { $0.hasPrefix("ts=") }.flatMap { Double($0.dropFirst(3)) }.map { $0 / 1e9 }
            return PointerEvent(kind, at: CGPoint(x: xy[0], y: xy[1]), time: ts ?? seconds)
        }
    }
}

/// 把事件按到达时刻喂给管线，超时拍在 deadline 那一刻准点喂（系统层的计时器就是这样），记下 App 实际会收到什么
struct CrossDeskReplay {
    /// 录制在 Mac 实体屏上（两块屏，短边约 1080 点）：一块范围盖住全部坐标，倍数按 2 算
    static let everywhere = TouchRegion(frame: CGRect(x: -3000, y: -3000, width: 6000, height: 6000), scale: 2)

    var pipeline = TouchPipeline(normalizers: [CrossDeskTouch.self])
    var regions = [Self.everywhere]
    /// 点击（抬起时补发按下、抬起）、选择（拖动时补发按下、当前）、右键、关窗、滚动开始、带惯性的松手、放行的原事件
    var clicks = 0, selections = 0, rightClicks = 0, closes = 0, slides = 0, flings = 0
    var passedMoves = 0, swallowedMoves = 0
    var slideStarts: [TimeInterval] = []
    private var time = 0.0

    mutating func run(_ events: [PointerEvent]) {
        for event in events {
            advance(to: event.time)
            let step = pipeline.take(event, from: 0, regions: regions)
            count(step, kind: event.kind, at: event.time)
            if event.kind == .move { if step.passOriginal { passedMoves += 1 } else { swallowedMoves += 1 } }
        }
        advance(to: time + 5)
    }

    private mutating func advance(to t: TimeInterval) {
        while let due = pipeline.deadline, due <= t {
            count(pipeline.tick(at: due, regions: regions), kind: nil, at: due)
        }
        while pipeline.isCoasting { _ = pipeline.momentumFrame() }
        time = t
    }

    private mutating func count(_ step: TouchStep, kind: PointerEvent.Kind?, at t: TimeInterval) {
        let commands = step.actions.compactMap { if case .perform(let c, _) = $0 { c } else { nil } }
        if commands.contains(.replayCurrent) {
            if kind == .leftUp { clicks += 1 } else { selections += 1 }
        }
        for command in commands {
            switch command {
            case .rightClick: rightClicks += 1
            case .closeWindow: closes += 1
            case .scroll(let s) where s.phase == .began: slides += 1; slideStarts.append(t)
            default: break
            }
        }
        if pipeline.isCoasting, !commands.isEmpty, commands.contains(where: { if case .scroll(let s) = $0 { s.phase == .ended } else { false } }) {
            flings += 1
        }
    }
}
