import CoreGraphics
import Foundation
import SnugCore
import Testing

private func at(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + s) }

@Suite("远控契约：每家适配器都要过的同一组断言")
struct RemoteContractTests {
    @Test("没人远程、读不到都不算在场，也不带控制端和推流屏", arguments: drivers)
    func absence(driver: any RemoteDriver) {
        for observation in [driver.idle(), driver.unreadable()] {
            #expect(!observation.present)
            #expect(observation.controllers.isEmpty)
            #expect(observation.streamedDisplay == nil)
        }
    }

    @Test("标准时序：连入 → 换控制端 → 断开 → 等待期内重连 → 读不到 → 断开 → 结束，会话变化和别家一样", arguments: drivers)
    func standardSequence(driver: any RemoteDriver) {
        let names: ([String]) -> [String] = { driver.namesControllers ? $0 : [] }
        let script: [(Double, RemoteObservation, [SessionTransition])] = [
            (0, driver.idle(), []),
            (0.5, driver.connected(controllers: ["iPhone"]), [.began(controllers: names(["iPhone"]))]),
            (1, driver.connected(controllers: ["iPad"]), driver.namesControllers ? [.controllersChanged(["iPad"])] : []),
            (1.5, driver.idle(), []),
            (2.6, driver.idle(), [.interrupted]),
            (5, driver.connected(controllers: ["iPad"]), [.resumed(controllers: names(["iPad"]))]),
            (5.5, driver.unreadable(), []),
            (6.6, driver.unreadable(), [.interrupted]),
            (21.7, driver.idle(), [.ended]),
        ]
        var session = RemoteSession()
        for (seconds, observation, expected) in script {
            #expect(session.update([RemoteReading(remote: driver.identity, observation: observation)], now: at(seconds)) == expected,
                    "第 \(seconds) 秒")
        }
    }

    @Test("推流屏：能报的报对，报不了的一直是 nil（不允许跳过不测）", arguments: drivers)
    func streamedDisplay(driver: any RemoteDriver) {
        let observation = driver.streaming(79)
        #expect(observation.present)
        #expect(observation.streamedDisplay == (driver.reportsStreamedDisplay ? 79 : nil))
        if !driver.reportsStreamedDisplay {
            #expect(driver.connected(controllers: ["iPhone"]).streamedDisplay == nil)
        }
    }

    @Test("选不到哪些屏：只在启动时认屏的远控要报（它启动后才建的 Snug 屏要提示重启，启动时就在的不提示），别的一直不报", arguments: drivers)
    func unreachableDisplays(driver: any RemoteDriver) {
        let later = driver.reaching(launched: [1, 367], online: [1, 367, 400])
        let same = driver.reaching(launched: [1, 367], online: [1, 367])
        #expect((later != nil) == driver.identity.seesScreensOnlyAtLaunch)
        if let later, let same {
            #expect(RemoteReading(remote: driver.identity, observation: later).unseen([367, 400]) == [400])
            #expect(RemoteReading(remote: driver.identity, observation: same).unseen([1, 367]).isEmpty)
        }
        if !driver.identity.seesScreensOnlyAtLaunch {
            for observation in [driver.idle(), driver.unreadable(), driver.connected(controllers: ["iPhone"]), driver.streaming(79)] {
                #expect(observation.unreachableDisplays == nil)
            }
        }
    }

    @Test("注入事件：认它自己注入的进程；本机的事件、Snug 自己的进程、别家远控的注入进程都不认", arguments: drivers)
    func injectedEvents(driver: any RemoteDriver) {
        let injector = driver.identity.injector
        #expect(injector.matches(executablePath: driver.injectorPath))
        #expect(!injector.matches(executablePath: ""))
        #expect(!injector.matches(executablePath: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"))
        #expect(!injector.matches(executablePath: "/Applications/Snug.app/Contents/MacOS/Snug"))
        for other in drivers where other.identity != driver.identity {
            #expect(!injector.matches(executablePath: other.injectorPath))
        }
    }

    @Test("手势：每家把手机上的点、长按松手、长按拖、单指滑整理完，经共用翻译器，App 收到的一样；整理交出的输入合标准语法",
          arguments: drivers, FingerGesture.allCases)
    func gestures(driver: any RemoteDriver, gesture: FingerGesture) {
        let events = driver.touchEvents(gesture)
        var normalizer = driver.identity.normalizer.init()
        var grammar = TouchGrammar()
        var problems: [String] = []
        let check = { (inputs: [TouchInput], synthesized: Bool) in problems += inputs.compactMap { grammar.check($0, synthesized: synthesized) } }
        for event in events {
            while let due = normalizer.deadline, due <= event.time { check(normalizer.tick(at: due), true) }
            let n = normalizer.normalize(event)
            check(n.before, true)
            check(n.current.map { [$0] } ?? [], false)
        }
        while let due = normalizer.deadline { check(normalizer.tick(at: due), true) }
        #expect(problems.isEmpty, "\(problems)")

        let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1)
        var pipeline = TouchPipeline(normalizers: [driver.identity.normalizer])
        var commands: [(TouchCommand, PointerEvent.Kind?)] = []
        let take = { (step: TouchStep, kind: PointerEvent.Kind?) in
            commands += step.actions.compactMap { if case .perform(let c, _) = $0 { (c, kind) } else { nil } }
        }
        for event in events {
            while let due = pipeline.deadline, due <= event.time { take(pipeline.tick(at: due, regions: [phone]), nil) }
            take(pipeline.take(event, from: 0, regions: [phone]), event.kind)
        }
        while let due = pipeline.deadline { take(pipeline.tick(at: due, regions: [phone]), nil) }
        let replays = commands.filter { $0.0 == .replayCurrent }
        let clicks = replays.filter { $0.1 == .leftUp }.count, selections = replays.count - clicks
        let rightClicks = commands.filter { if case .rightClick = $0.0 { true } else { false } }.count
        let scrolls = commands.filter { if case .scroll(let s) = $0.0 { s.phase == .began } else { false } }.count
        let expected: (clicks: Int, rightClicks: Int, selections: Int, scrolls: Int) = switch gesture {
        case .tap: (1, 0, 0, 0)
        case .holdRelease: (0, 1, 0, 0)
        case .holdDrag: (0, 0, 1, 0)
        case .slide: (0, 0, 0, 1)
        }
        #expect(clicks == expected.clicks && rightClicks == expected.rightClicks && selections == expected.selections && scrolls == expected.scrolls,
                "点击 \(clicks)、右键 \(rightClicks)、选择 \(selections)、滚动 \(scrolls)")
    }

    @Test("它自己的 App 不出现在资源库里", arguments: drivers)
    func excludedFromLibrary(driver: any RemoteDriver) {
        let own = InstalledApp(AppInfo(bundleID: driver.appBundleID, name: driver.identity.displayName, path: "/Applications/x.app"), english: "x")
        #expect(AppList.sorted([own], excluding: driver.identity.bundleIDs).isEmpty)
        let running = RunningApp(pid: 1, app: own.app, windows: [])
        #expect(AppList.refreshed([running], shown: [], reorder: true, excluding: driver.identity.bundleIDs).isEmpty)
    }

    @Test("每次观测都带信号快照：写进连入、断开日志，排查误判用", arguments: drivers)
    func evidence(driver: any RemoteDriver) {
        for observation in [driver.idle(), driver.unreadable(), driver.connected(controllers: ["iPhone"]), driver.streaming(79)] {
            #expect(!observation.evidence.isEmpty)
        }
    }

    @Test("身份：日志名、界面名不为空，日志名不含空格（命令行参数、日志解析都靠它），各家不重名")
    func identities() {
        let names = drivers.map { $0.identity.logName.lowercased() }
        #expect(Set(names).count == names.count)
        for driver in drivers {
            #expect(!driver.identity.logName.isEmpty && !driver.identity.logName.contains(" "))
            #expect(!driver.identity.displayName.isEmpty)
        }
    }
}
