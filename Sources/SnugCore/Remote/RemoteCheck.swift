// 远控兼容自检的报告（scripts/snug remote-check <名字> → Snug --check-remote <名字>）：远控一更新，把 Snug 依赖它的几处逐项核对。
// 各家自己收集事实、逐项判定（UU 见 UUCheck，CrossDesk 见 CrossDeskCheck），条目和报告的写法在这里共用
import Foundation

public enum RemoteCheck {
    public enum Status: Equatable, Sendable {
        case ok, warn, fail, info

        public var symbol: String {
            switch self {
            case .ok: "✅"
            case .warn: "⚠️"
            case .fail: "❌"
            case .info: "ℹ️"
            }
        }
    }

    public struct Item: Equatable, Sendable {
        public var status: Status
        public var title: String
        public var detail: String

        public init(status: Status, title: String, detail: String) {
            self.status = status
            self.title = title
            self.detail = detail
        }
    }

    /// 第一项：没装。其余各项无从核对，各家只报这一项
    public static func notInstalled(_ remote: RemoteIdentity, bundleID: String) -> Item {
        Item(status: .fail, title: remote.displayName, detail: "没装（按 \(bundleID) 找不到），其余各项无从核对")
    }

    /// 第一项：装了什么版本、和上次核对过的比，这次核对哪一段（scope：「最近 4 小时」之类）
    public static func installed(_ remote: RemoteIdentity, version: String, verified: String, scope: String) -> Item {
        let note = version == verified ? "即上次核对的版本" : "上次核对的是 \(verified)"
        return Item(status: .ok, title: remote.displayName, detail: "版本 \(version)（\(note)）；核对范围：\(scope)")
    }

    /// 报告里的时刻（时:分）
    public static func clock(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// 报告正文：标题（「<远控> 兼容自检」）、结论、逐项
    public static func report(_ items: [Item], remote: RemoteIdentity, hours: Int, at date: Date) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "MM-dd HH:mm"
        let fails = items.filter { $0.status == .fail }.count
        let warns = items.filter { $0.status == .warn }.count
        let verdict = fails > 0 ? "发现 \(fails) 项问题" : warns > 0 ? "未发现问题，\(warns) 项需留意" : "未发现兼容问题"
        return (["\(remote.displayName) 兼容自检 · \(stamp.string(from: date)) · 回看 \(hours) 小时", "结论：\(verdict)", ""]
            + items.map { "\($0.status.symbol) \($0.title)：\($0.detail)" }).joined(separator: "\n")
    }

    /// 有一项不通过：命令以 1 退出
    public static func exitCode(_ items: [Item]) -> Int32 {
        items.contains { $0.status == .fail } ? 1 : 0
    }
}
