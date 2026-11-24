import Foundation
import Testing
@testable import SnugCore

@Suite("远控端口 RemoteAdapter")
struct RemoteAdapterTests {
    @Test("远控选不到的 Snug 屏：它报的选不到的里面是 Snug 的那几块；不知道（nil）时一块都不算")
    func unseenScreens() {
        #expect(reading(fakeRemote, unreachable: [368, 5]).unseen([367, 368]) == [368])
        #expect(reading(fakeRemote, unreachable: [368]).unseen([]).isEmpty)
        #expect(reading(fakeRemote, unreachable: nil).unseen([367]).isEmpty)
    }

    @Test("该提示重启哪家：没人远程时问每一家；远程中只问这次远程的那家，别家选不到为别人建的屏不提示")
    func blind() {
        let readings = [reading(fakeRemote, unreachable: nil), reading(otherRemote, unreachable: [368])]
        #expect(RemoteReading.blind(readings, owner: nil, snugDisplays: [367, 368])?.remote == otherRemote)
        #expect(RemoteReading.blind(readings, owner: nil, snugDisplays: [367])?.displays == nil)
        #expect(RemoteReading.blind(readings, owner: fakeRemote, snugDisplays: [367, 368]) == nil)
        #expect(RemoteReading.blind(readings, owner: otherRemote, snugDisplays: [368])?.displays == [368])
    }

    private func reading(_ remote: RemoteIdentity, unreachable: Set<DisplayID>?) -> RemoteReading {
        RemoteReading(remote: remote, observation: RemoteObservation(present: false, controllers: [], streamedDisplay: nil, evidence: "",
                                                                     unreachableDisplays: unreachable))
    }

    @Test("注入事件来源：只认可执行文件名完全对上的进程；读不到路径、同名目录、名字只是前缀都不认")
    func injectedEventSource() {
        let source = fakeRemote.injector
        #expect(source.matches(executablePath: "/Applications/甲.app/Contents/Helpers/JiaServer"))
        #expect(source.matches(executablePath: "JiaServer"))
        #expect(!source.matches(executablePath: ""))
        #expect(!source.matches(executablePath: "/Applications/甲.app/Contents/MacOS/甲"))
        #expect(!source.matches(executablePath: "/tmp/JiaServer/helper"))
        #expect(!source.matches(executablePath: "/Applications/甲.app/Contents/Helpers/JiaServerAgent"))
        #expect(!source.matches(executablePath: "/Applications/甲.app/Contents/Helpers/jiaserver"))
    }
}
