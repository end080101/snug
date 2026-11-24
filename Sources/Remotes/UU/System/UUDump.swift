// --dump-remote uu：打印从 UU远程 读到的东西和此刻的屏幕。只读，不点 UU、不碰屏幕
import CoreGraphics
import Foundation
import RemoteUU
import SnugCore
import SnugSystem

@MainActor
package enum UUDump {
    package static func run() -> Int32 {
        print("覆盖窗口：\(UURemoteApp.overlayVisible() ? "在屏" : "没有")")
        print("屏幕：")
        RemoteCheckTools.displayLines().forEach { print($0) }
        guard AX.isTrusted else {
            print("没有辅助功能权限，读不到 UU远程 的界面")
            return 1
        }
        guard let pid = UURemoteApp.pid() else {
            print("UU远程 没有在运行")
            return 1
        }
        guard let windows = UUAccessibility.windows(pid: pid) else {
            print("界面：读不到（UU远程 没有窗口、没响应，或界面超出遍历上限）")
            return 0
        }
        // 打出界面树里的文字、表格和行：没认出控制端时，看 UU 停在哪一页
        print("界面：")
        treeLines(windows).forEach { print($0) }
        guard case .shown(let names) = ControllerTable(windows: windows) else {
            print("控制端：未识别（只认本机被控页里「本机被控中」那张表：远程中出现这一行，多半是 UU 停在首页、错误页、别的设备的详情页，或收起了被控页；"
                + "上面确实有本机被控页和它的表，才是认不出 UU 的界面）")
            return 0
        }
        print("控制端：")
        for name in names { print("  \(name)") }
        return 0
    }

    /// 界面树里的文字、表格和行，一行一个；别的元素不占一层缩进（兼容自检的取证材料也用）
    static func treeLines(_ windows: [UUElement]) -> [String] {
        var lines: [String] = []
        func walk(_ element: UUElement, depth: Int) {
            let label: String? = switch element.kind {
            case .text(let text): text.isEmpty ? nil : "「\(text)」"
            case .table: "表格"
            case .row: "行"
            case .other: nil
            }
            if let label { lines.append(String(repeating: "  ", count: depth) + label) }
            for child in element.children { walk(child, depth: label == nil ? depth : depth + 1) }
        }
        for window in windows { walk(window, depth: 1) }
        return lines
    }
}
