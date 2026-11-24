import Foundation
import Testing
@testable import RemoteUU
@testable import SnugCore

/// 距某个固定时刻多少秒（会话层只看间隔）
private func at(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + s) }

@Suite("UU 的三路信号 UUSignals")
struct UUSignalsTests {
    @Test("信号快照写进日志用的描述：区分读不到 / 未识别 / 具体名字")
    func snapshotDescription() {
        #expect(UUSignals(overlayVisible: true, controllers: .unreadable, captureActive: nil).description == "overlay=是 控制端=读不到 capture=未知")
        #expect(UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: false).description == "overlay=否 控制端=未识别 capture=否")
        #expect(UUSignals(overlayVisible: false, controllers: .shown(["iPhone", "iPad"]), captureActive: true).description == "overlay=否 控制端=iPhone,iPad capture=是")
    }

    @Test("在场只认正面证据：覆盖窗口、认出控制端、推流进行中，任一路就算；读不到、没认出都不算")
    func presenceNeedsPositiveEvidence() {
        #expect(UUSignals(overlayVisible: true, controllers: .unreadable, captureActive: nil).isPresent)
        #expect(UUSignals(overlayVisible: false, controllers: .shown(["iPhone"]), captureActive: nil).isPresent)
        #expect(UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: true).isPresent)
        #expect(UUSignals(overlayVisible: false, controllers: .unreadable, captureActive: true).isPresent)
        for table in [ControllerTable.unreadable, .unrecognized] {
            for captureActive in [nil, false] as [Bool?] {
                #expect(!UUSignals(overlayVisible: false, controllers: table, captureActive: captureActive).isPresent)
            }
        }
    }

    @Test("交给核心的观测：在场照三路信号，控制端只取认出的名字，推流屏原样带上，快照就是 description")
    func observation() {
        let streaming = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: true)
        #expect(streaming.observation(streamedDisplay: 79)
                == RemoteObservation(present: true, controllers: [], streamedDisplay: 79, evidence: streaming.description))
        let named = UUSignals(overlayVisible: false, controllers: .shown(["iPhone", "iPad"]), captureActive: nil)
        #expect(named.observation(streamedDisplay: nil).controllers == ["iPhone", "iPad"])
        #expect(named.observation(streamedDisplay: nil).present)
        for table in [ControllerTable.unreadable, .unrecognized] {
            let unknown = UUSignals(overlayVisible: false, controllers: table, captureActive: nil).observation(streamedDisplay: nil)
            #expect(!unknown.present)
            #expect(unknown.controllers.isEmpty)
        }
        #expect(UUSignals(overlayVisible: true, controllers: .unreadable, captureActive: false).observation(streamedDisplay: nil).present)
        #expect(UUSignals(overlayVisible: false, controllers: .unreadable, captureActive: true).observation(streamedDisplay: 79)
                == RemoteObservation(present: true, controllers: [], streamedDisplay: 79, evidence: "overlay=否 控制端=读不到 capture=是"))
    }

    @Test("身份：日志名「UU」让日志逐字不变；资源库排除 UU 主程序；手势只接管 UURemoteServer")
    func identity() {
        #expect(UURemote.identity.logName == "UU")
        #expect(UURemote.identity.displayName == "UU远程")
        #expect(UURemote.identity.bundleIDs == ["com.netease.uuremote"])
        #expect(UURemote.identity.injector.matches(executablePath: "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"))
        #expect(!UURemote.identity.injector.matches(executablePath: "/Applications/UURemote.app/Contents/MacOS/UURemote"))
    }

    @Test("往返：信号快照写进日志再读回，覆盖窗口和推流两路对得上；写法对不上读成 nil",
          arguments: [true, false] as [Bool])
    func loggedRoundTrip(overlay: Bool) {
        for capture in [true, false, nil] as [Bool?] {
            for table in [ControllerTable.unreadable, .unrecognized, .shown(["MacBook Pro", "iPhone"])] {
                let back = UUSignals.logged(UUSignals(overlayVisible: overlay, controllers: table, captureActive: capture).description)
                #expect(back?.overlay == overlay)
                #expect(back.map { $0.capture == capture } == true)
            }
        }
        #expect(UUSignals.logged("信号=一") == nil)
        #expect(UUSignals.logged("overlay=也许 控制端=未识别 capture=是") == nil)
    }

    @Test("端到端（回归 #1）：UU 没认出控制端、推流一直在，远程不断开；停流后照常 interrupted、ended")
    func unrecognizedTableKeepsStreamingSession() {
        var s = RemoteSession()
        func update(_ signals: UUSignals, _ seconds: Double) -> [SessionTransition] {
            s.update([RemoteReading(remote: UURemote.identity, observation: signals.observation(streamedDisplay: nil))], now: at(seconds))
        }
        let streaming = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: true)
        let stopped = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: false)
        #expect(update(streaming, 0) == [.began(controllers: [])])
        for seconds in [0.5, 59.5, 60, 60.5, 75.6, 300] {
            #expect(update(streaming, seconds) == [])
        }
        #expect(s.inEpisode)
        #expect(update(stopped, 300.5) == [])
        #expect(update(stopped, 301.6) == [.interrupted])
        #expect(update(stopped, 316.7) == [.ended])
    }
}
