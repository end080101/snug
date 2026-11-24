import CoreGraphics
import Testing
@testable import SnugCore

@Suite("指针落点 CursorHome")
struct CursorHomeTests {
    private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let other = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test("指针在留下的屏上：不动")
    func staysOnKept() {
        #expect(CursorHome.landing(pointer: CGPoint(x: 100, y: 100), kept: [main], main: main) == nil)
    }

    @Test("指针落在要撤的屏上：挪到主屏中央（issue #29）")
    func leavesRemovedScreen() {
        #expect(CursorHome.landing(pointer: CGPoint(x: 1600, y: 30), kept: [main], main: main) == CGPoint(x: 756, y: 491))
    }

    @Test("主屏就是要撤的那块：挪到第一块留下的屏中央")
    func fallsBackToFirstKept() {
        #expect(CursorHome.landing(pointer: CGPoint(x: 1600, y: 30), kept: [other], main: .zero) == CGPoint(x: 50, y: 50))
    }

    @Test("一块屏都不剩：不挪")
    func nothingLeft() {
        #expect(CursorHome.landing(pointer: CGPoint(x: 1600, y: 30), kept: [], main: .zero) == nil)
    }

    @Test("没人远程时滑进看不见的屏：退回看得见的屏上最近的一点（像碰到墙）；在看得见的屏上不动；一块看得见的都没有不动")
    func edge() {
        let external = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        // 从内建屏右边滑进右边的虚拟屏：退到内建屏最右一列
        #expect(CursorHome.edge(pointer: CGPoint(x: 1530, y: 400), visible: [main]) == CGPoint(x: 1511, y: 400))
        // 两块看得见的屏取更近的那块
        #expect(CursorHome.edge(pointer: CGPoint(x: 1600, y: -300), visible: [main, external]) == CGPoint(x: 1600, y: -200))
        #expect(CursorHome.edge(pointer: CGPoint(x: 100, y: 100), visible: [main]) == nil)
        #expect(CursorHome.edge(pointer: CGPoint(x: 3000, y: 3000), visible: []) == nil)
    }
}
