import CoreGraphics
import Testing
@testable import SnugCore

@Suite("窗口在哪 WindowSpot")
struct WindowSpotTests {
    /// 内建屏在左，Snug 的电脑屏接在右边（全局坐标，左上原点，和窗口服务器报的窗口位置同一个坐标系）
    private let builtIn: DisplayID = 1
    private let computer: DisplayID = 22
    private let builtInBounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let computerBounds = CGRect(x: 1512, y: 0, width: 1470, height: 956)
    private var displays: [(id: DisplayID, bounds: CGRect)] { [(builtIn, builtInBounds), (computer, computerBounds)] }

    private func spot(_ frame: CGRect, shown: Bool) -> WindowSpot { WindowSpot(frame: frame, shown: shown, displays: displays) }

    @Test("露着的窗口：中点落在哪块屏就在哪块屏")
    func shown() {
        #expect(spot(CGRect(x: 100, y: 100, width: 800, height: 600), shown: true) == .shown(builtIn))
        #expect(spot(CGRect(x: 1700, y: 200, width: 800, height: 600), shown: true) == .shown(computer))
    }

    @Test("跨两块屏的窗口按中点算：大半在电脑屏上就算电脑屏")
    func straddling() {
        #expect(spot(CGRect(x: 1300, y: 100, width: 800, height: 600), shown: true) == .shown(computer))
        #expect(spot(CGRect(x: 900, y: 100, width: 800, height: 600), shown: true) == .shown(builtIn))
    }

    @Test("没露着、铺满整块电脑屏：在这块屏的全屏空间里，屏切回普通桌面时被盖住（11-17 实测：加屏后 Safari 的全屏空间挪了过来）")
    func coveredFullScreen() {
        #expect(spot(computerBounds, shown: false) == .fullScreen(computer))
        #expect(spot(builtInBounds, shown: false) == .fullScreen(builtIn))
    }

    @Test("全屏空间正露着：算露着，不算被盖住")
    func shownFullScreen() {
        #expect(spot(computerBounds, shown: true) == .shown(computer))
    }

    @Test("没露着、没铺满（别的桌面、最小化、藏起来的）：远端看不见")
    func hidden() {
        #expect(spot(CGRect(x: 1700, y: 200, width: 800, height: 600), shown: false) == .hidden)
        // 只扣掉菜单栏的「最大化」窗口不是全屏
        #expect(spot(CGRect(x: 1512, y: 33, width: 1470, height: 923), shown: false) == .hidden)
    }

    @Test("和一块屏一样大、却不在那块屏的位置上：不是它的全屏空间")
    func sameSizeElsewhere() {
        let shifted = CGRect(origin: CGPoint(x: 1600, y: 0), size: computerBounds.size)
        #expect(spot(shifted, shown: false) == .hidden)
    }

    @Test("中点不在任何一块屏上（屏刚撤掉，窗口还没被挪回来）：当作看不见")
    func offEveryDisplay() {
        #expect(spot(CGRect(x: 4000, y: 100, width: 800, height: 600), shown: true) == .hidden)
        #expect(WindowSpot(frame: computerBounds, shown: false, displays: []) == .hidden)
    }

    @Test("镜像的屏范围重合：取系统先列出的那块（同 CGGetDisplaysWithPoint）")
    func mirrored() {
        let mirror: DisplayID = 5
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(WindowSpot(frame: frame, shown: true, displays: [(builtIn, builtInBounds), (mirror, builtInBounds)]) == .shown(builtIn))
        #expect(WindowSpot(frame: frame, shown: true, displays: [(mirror, builtInBounds), (builtIn, builtInBounds)]) == .shown(mirror))
    }
}
