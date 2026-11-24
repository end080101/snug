// 电脑屏的资源库给每个窗口标「在哪」：在哪块屏、露没露着、是不是在那块屏的全屏空间里。
// 窗口的位置、屏的范围都问窗口服务器（全局坐标，左上原点，见 WindowService.spots），这里只做判断
import CoreGraphics

/// 一个窗口此刻在哪
public enum WindowSpot: Equatable, Sendable {
    /// 露在这块屏此刻的桌面里
    case shown(DisplayID)
    /// 在这块屏的全屏空间里：没露着、铺满整块屏。Snug 的屏一加，macOS 会把原主屏上的全屏空间挪过来（实测），
    /// 屏切回普通桌面时全屏的窗口就被盖住了。电脑屏的资源库对它「切换」：切进那个全屏空间，不退出全屏
    case fullScreen(DisplayID)
    /// 没露着（别的桌面、最小化、藏起来的），或中点不在任何一块屏上：远端的人看不见
    case hidden

    /// 按窗口中点落在哪块屏算（同 CGGetDisplaysWithPoint：镜像的屏范围重合，取先列出的那块）。
    /// displays：各块在线屏的范围，按系统列出的顺序
    public init(frame: CGRect, shown: Bool, displays: [(id: DisplayID, bounds: CGRect)]) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let display = displays.first(where: { $0.bounds.contains(center) }) else {
            self = .hidden
            return
        }
        // 全屏窗口的框和屏的范围分毫不差（窗口服务器报的都是整点）；只扣掉菜单栏的「最大化」窗口不算
        if shown {
            self = .shown(display.id)
        } else if frame == display.bounds {
            self = .fullScreen(display.id)
        } else {
            self = .hidden
        }
    }
}
