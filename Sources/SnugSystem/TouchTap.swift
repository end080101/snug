// 手势翻译的系统部分：一个事件监听，只接管登记的远控注入的指针事件，按是哪一家交给手势管线（TouchPipeline：
// 这家的整理 → 共用的翻译器），再照它交出的一步放行或吞掉原事件、补发点击、右键或滚动（事件怎么读、怎么拼见 TouchEvents）。
// 管的范围是每块要翻译手势的屏一块；本机的触控板、鼠标一律不碰。
// 跑在独立线程上：主线程会被建屏、搬窗口卡住，监听回调一慢，系统会让全机的鼠标跟着卡
import CoreGraphics
import Foundation
import os
import SnugCore

/// 主线程用的开关。每次开启是一个独立的监听会话：关掉马上再开，新旧两个线程互不共用状态
@MainActor
public final class TouchTap {
    /// 手势翻译管的范围（CGEvent 坐标），每块要翻译手势的屏一块。主线程写，监听线程读
    private let regions = OSAllocatedUnfairLock<[TouchRegion]>(initialState: [])
    private var session: TapSession?
    /// 各家已登记的远控：认哪个进程注入的事件、怎么整理，按登记顺序
    private let remotes: [RemoteIdentity]
    /// 手机上点了屏上那个窗口的关闭按钮（核对过、点击已经吞掉了），交回窗口编号：在主线程上调
    public var onCloseWindow: ((UInt32) -> Void)?
    /// 手势层要提醒用户的话变了（见 TouchNormalizer.advice），nil = 不用提醒：在主线程上调
    public var onAdvice: ((String?) -> Void)?
    private var advice: String?

    public init(remotes: [RemoteIdentity]) {
        self.remotes = remotes
    }

    /// 只在这几块范围里翻译手势，一块都没有就关掉监听。范围变了（换档、屏幕重排）照样调，监听不用重开。
    /// 要翻译却建不起事件监听（多半是没有辅助功能权限）时交回 false，下次调用再试
    public func setRegions(_ regions: [TouchRegion]) -> Bool {
        self.regions.withLock { $0 = regions }
        guard !regions.isEmpty else {
            stop()
            return true
        }
        return start()
    }

    /// 起监听线程，等它报告监听建没建成
    private func start() -> Bool {
        guard session == nil else { return true }
        let next = TapSession(regions: regions, remotes: remotes) { [weak self] window in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onCloseWindow?(window) } }
        } adviceChanged: { [weak self] advice in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.report(advice) } }
        }
        guard next.start() else {
            Log.error("手势翻译开不起来：建事件监听失败（多半是没有辅助功能权限）")
            return false
        }
        session = next
        Log.info("手势翻译已开启（只接管 \(remotes.map(\.injector.executableName).joined(separator: "、")) 发来、在 Snug 屏里的操作）")
        return true
    }

    /// 一次远程结束：手势层从头认（见 TouchPipeline.reset），旧的提醒收起。监听没开时没有要清的
    public func remoteEnded() {
        session?.reset()
    }

    private func stop() {
        guard let session else { return }
        session.stop()
        self.session = nil
        Log.info("手势翻译已关闭")
        report(nil)
    }

    private func report(_ next: String?) {
        // 监听已关时，关之前排进主线程的变化不再算数
        let next = session == nil ? nil : next
        guard next != advice else { return }
        advice = next
        Log.info(next.map { "手势层提醒用户：\($0)" } ?? "手势层的提醒已收起")
        onAdvice?(next)
    }
}

/// 一次监听：自己的线程、自己的 run loop、自己的状态机。除了 start / stop，其余都只在这个线程上跑
private final class TapSession: @unchecked Sendable {
    private let regions: OSAllocatedUnfairLock<[TouchRegion]>
    private let closeWindow: @Sendable (UInt32) -> Void
    private let adviceChanged: @Sendable (String?) -> Void
    /// 监听线程的 run loop：start 等它建好才返回，之后只读
    private var runLoop: CFRunLoop?

    /// 监听的事件种类：各家整理要看的并集
    private let mask: CGEventMask

    // 以下只在监听线程上访问
    private var tap: CFMachPort?
    private var pipeline: TouchPipeline
    private var heldPress: CGEvent?
    private var coastTimer: CFRunLoopTimer?
    /// 整理要的超时拍（比如停多久算松手）：第一次有人要时才建
    private var deadlineTimer: CFRunLoopTimer?
    private var injected: InjectedEvents
    private var advice: String?

    init(regions: OSAllocatedUnfairLock<[TouchRegion]>, remotes: [RemoteIdentity], closeWindow: @escaping @Sendable (UInt32) -> Void,
         adviceChanged: @escaping @Sendable (String?) -> Void) {
        self.regions = regions
        injected = InjectedEvents(injectors: remotes.map(\.injector))
        pipeline = TouchPipeline(normalizers: remotes.map(\.normalizer))
        mask = TouchEvents.mask(for: TouchPipeline.kinds(of: remotes.map(\.normalizer)))
        self.closeWindow = closeWindow
        self.adviceChanged = adviceChanged
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let ok = installTap()
            if ok { runLoop = CFRunLoopGetCurrent() }
            ready.signal()
            if ok { CFRunLoopRun() }
        }
        thread.name = "com.zephyr4123.snug.touch"
        thread.qualityOfService = .userInteractive
        thread.start()
        // 建监听是同步的、很快，不设超时：设了超时反而会在超时后留下一个关不掉的监听。
        // signal / wait 也保证监听线程对 runLoop 的写入在这里可见
        ready.wait()
        return runLoop != nil
    }

    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            tap = nil
            stopCoasting()
            if let deadlineTimer { CFRunLoopTimerInvalidate(deadlineTimer) }
            deadlineTimer = nil
            heldPress = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// 在监听线程上清掉这次远程留下的：管线从头来，扣着的按下、惯性作废。和事件回调同一线程，不会撞上处理到一半的事件
    func reset() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            pipeline.reset()
            heldPress = nil
            stopCoasting()
            settle()
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func installTap() -> Bool {
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        return Unmanaged<TapSession>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.warn("手势翻译的事件监听被系统停用（\(type == .tapDisabledByTimeout ? "回调超时" : "用户输入")），已重新开启")
            return pass
        }
        guard let kind = TouchEvents.kind(of: type), !TouchEvents.isReplay(event), let source = injected.source(of: event) else { return pass }

        let raw = PointerEvent(kind, at: event.location, time: ProcessInfo.processInfo.systemUptime)
        let step = pipeline.take(raw, from: source, regions: regions.withLock { $0 })
        run(step, original: event)
        return step.passOriginal ? pass : nil
    }

    /// 照管线交出的一步做。original：这一步对应的原事件；超时拍没有
    private func run(_ step: TouchStep, original: CGEvent?) {
        for action in step.actions {
            switch action {
            case .holdOriginal: heldPress = original?.copy()
            case .perform(let command, let region): perform(command, current: original, region: region)
            case .dropHeld: heldPress = nil
            }
        }
        settle()
    }

    /// 管线变了之后：惯性、超时拍的计时器跟上，提醒变了报给主线程
    private func settle() {
        if pipeline.isCoasting { startCoasting() }
        scheduleDeadline()
        if pipeline.advice != advice {
            advice = pipeline.advice
            adviceChanged(advice)
        }
    }

    private func perform(_ command: TouchCommand, current: CGEvent?, region: TouchRegion?) {
        switch command {
        case .replayPress:
            TouchEvents.post(heldPress)
            heldPress = nil
        case .replayCurrent:
            guard let current else {
                Log.error("手势翻译要补发当前事件，可这一步没有原事件（超时拍）：跳过")
                return
            }
            TouchEvents.post(current.copy())
        case .rightClick(let point):
            TouchEvents.rightClick(at: point).forEach(TouchEvents.post)
        case .scroll(let step):
            TouchEvents.post(TouchEvents.scroll(step))
        case .closeWindow(let point):
            // 按钮位置是铺好时读的：点下去这一刻再问一次窗口服务器（不经过 App，很快），对不上就照常点
            if let button = region?.closeButton, button.isFrontmost(at: point, onScreen: Self.onScreen()) {
                closeWindow(button.window)
            } else {
                Log.info("点在屏上那个窗口原来的关闭按钮处，但那里已经不是它的关闭按钮（挪走、被盖住或全屏了），照常点击")
                perform(.replayPress, current: current, region: region)
                perform(.replayCurrent, current: current, region: region)
            }
        }
    }

    /// 指针那一层：窗口服务器画指针用的窗口，总在最前、跟着指针走，但不接点击
    private static let pointerLevel = Int(CGWindowLevelForKey(.cursorWindow))

    /// 窗口服务器里此刻在屏上的窗口，从前到后
    private static func onScreen() -> [(id: UInt32, frame: CGRect, isPointer: Bool)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return (list ?? []).compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (id, frame, ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) >= pointerLevel)
        }
    }

    /// 惯性：在监听线程的 run loop 上按 60fps 走，走完自己停
    private func startCoasting() {
        guard coastTimer == nil else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 1 / Momentum.frameRate, 0, 0) { [self] _ in
            if let step = pipeline.momentumFrame() { TouchEvents.post(TouchEvents.scroll(step)) }
            if !pipeline.isCoasting { stopCoasting() }
        }
        coastTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    }

    private func stopCoasting() {
        guard let timer = coastTimer else { return }
        CFRunLoopTimerInvalidate(timer)
        coastTimer = nil
    }

    /// 超时拍：把计时器拨到整理要的下一个时刻（单调钟换算成 CFAbsoluteTime），没人要就拨到很远。
    /// 只有直通的整理时一直没人要，计时器从不建
    private func scheduleDeadline() {
        guard let due = pipeline.deadline else {
            if let deadlineTimer { CFRunLoopTimerSetNextFireDate(deadlineTimer, .greatestFiniteMagnitude) }
            return
        }
        let fire = CFAbsoluteTimeGetCurrent() + max(0, due - ProcessInfo.processInfo.systemUptime)
        if let deadlineTimer {
            CFRunLoopTimerSetNextFireDate(deadlineTimer, fire)
            return
        }
        // 间隔给得很大：每次都由 scheduleDeadline 拨下一次
        let timer = CFRunLoopTimerCreateWithHandler(nil, fire, 1e9, 0, 0) { [self] _ in
            let step = pipeline.tick(at: ProcessInfo.processInfo.systemUptime, regions: regions.withLock { $0 })
            run(step, original: nil)
        }
        deadlineTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    }
}
