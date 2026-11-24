import Foundation
import Testing
@testable import SnugCore

@Suite("远控端口 RemoteAdapter")
struct RemoteAdapterTests {
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
