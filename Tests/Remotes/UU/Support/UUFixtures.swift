import Foundation

/// UU 的推流日志夹具：来自本机 `log show --style ndjson --predicate 'process == "UURemoteServer" …'`。
/// 2224 是 2026-11-23 按现在的关键字录的；1901、2000 是 2026-11-12 按当时的关键字录的，只有开推、停和编码会话的行（解析时忽略），
/// 没有屏的描述、登记输出和释放。只保留时间、类型、子系统、进程路径和消息正文，不含 IP、用户名、主目录路径
enum UUFixtures {
    /// uuremoteserver-<name>.ndjson 的每一行
    static func lines(_ name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: "uuremoteserver-\(name)", withExtension: "ndjson", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}
