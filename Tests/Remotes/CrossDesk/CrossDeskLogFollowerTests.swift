import Foundation
import RemoteCrossDesk
import Testing

private func bytes(_ s: String) -> Data { Data(s.utf8) }

@Suite("跟着读 CrossDesk 日志")
struct CrossDeskLogFollowerTests {
    @Test("头一次只读末尾一段：从文件中间开始时丢掉开头的半截行；文件不大从头读")
    func firstReadFromTail() {
        var big = CrossDeskLogFollower()
        let size = CrossDeskLogFollower.initialWindow + 100
        #expect(big.range(file: 7, size: size) == 100..<size)
        #expect(big.lines(from: bytes("截的行\n第一行\n第二行\n")) == ["第一行", "第二行"])
        var small = CrossDeskLogFollower()
        #expect(small.range(file: 7, size: 12) == 0..<12)
        #expect(small.lines(from: bytes("整行\n")) == ["整行"])
    }

    @Test("从中间读、头一段里还没有换行：整段都是半截行，丢掉，下一段从换行之后接着")
    func partialHeadSpansReads() {
        var f = CrossDeskLogFollower()
        let window = CrossDeskLogFollower.initialWindow, size = window + 9
        #expect(f.range(file: 7, size: size) == 9..<size)
        #expect(f.lines(from: Data(repeating: 0x41, count: Int(window))).isEmpty)
        let next = bytes("的\n新行\n")
        #expect(f.range(file: 7, size: size + UInt64(next.count)) == size..<(size + UInt64(next.count)))
        #expect(f.lines(from: next) == ["新行"])
    }

    @Test("半行攒到下一拍拼回来；没长不读")
    func pendingLineJoins() {
        var f = CrossDeskLogFollower()
        let first = bytes("一行\n半"), second = bytes("行\n")
        #expect(f.range(file: 7, size: 0) == nil)
        #expect(f.range(file: 7, size: 0) == nil)
        #expect(f.range(file: 7, size: UInt64(first.count)) == 0..<UInt64(first.count))
        #expect(f.lines(from: first) == ["一行"])
        let total = UInt64(first.count + second.count)
        #expect(f.range(file: 7, size: total) == UInt64(first.count)..<total)
        #expect(f.lines(from: second) == ["半行"])
    }

    @Test("换了文件（滚动出新的 crossdesk.log）、文件被截短：从头读，攒着的半行作废")
    func rotationAndTruncation() {
        var f = CrossDeskLogFollower()
        _ = f.range(file: 7, size: 6)
        _ = f.lines(from: bytes("旧\n半"))
        #expect(f.range(file: 8, size: 4) == 0..<4)
        #expect(f.lines(from: bytes("新\n")) == ["新"])
        #expect(f.range(file: 8, size: 2) == 0..<2)
    }
}
