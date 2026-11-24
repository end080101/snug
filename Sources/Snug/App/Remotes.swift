// 唯一登记远控的地方：会话、手势翻译、资源库的排除名单、诊断命令都从这里取。
// 接一家新的远控：在 Sources/Remotes 下建它的两个目标，在这里加一行，再给契约测试加一个驱动（见 docs/remotes/README.md）
import Foundation
import RemoteCrossDeskSystem
import RemoteUUSystem
import SnugCore

@MainActor
enum Remotes {
    @MainActor
    struct Entry {
        let adapter: any RemoteAdapter.Type
        /// --dump-remote：打印读到的原始信号，返回退出码
        let dump: @MainActor () -> Int32
        /// --check-remote：兼容自检，返回退出码
        let check: @MainActor (_ hours: Int) -> Int32

        var identity: RemoteIdentity { adapter.identity }
        /// 命令行里的名字：日志名的小写
        var name: String { identity.logName.lowercased() }
    }

    /// 登记顺序就是归属顺序：两家同时报在场时归前面那家
    static let all: [Entry] = [
        Entry(adapter: UURemoteAdapter.self, dump: UUDump.run, check: UUCheckRun.run(hours:)),
        Entry(adapter: CrossDeskRemoteAdapter.self, dump: CrossDeskDump.run, check: CrossDeskCheckRun.run(hours:)),
    ]

    static var names: [String] { all.map(\.name) }

    static func dump(_ name: String) -> Int32 {
        entry(name)?.dump() ?? 2
    }

    static func check(_ name: String, hours: Int) -> Int32 {
        entry(name)?.check(hours) ?? 2
    }

    private static func entry(_ name: String) -> Entry? {
        if let entry = all.first(where: { $0.name == name.lowercased() }) { return entry }
        FileHandle.standardError.write(Data("没有登记叫「\(name)」的远控（可选：\(names.joined(separator: " / "))）\n".utf8))
        return nil
    }
}
