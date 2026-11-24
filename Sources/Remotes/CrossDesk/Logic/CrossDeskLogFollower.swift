// 跟着读 crossdesk.log 新追加的行，纯值：这一拍从哪读到哪、读到的字节怎么拼成完整的行。
// 读文件在系统部分（CrossDeskLogTail），这里只做判断，好单测。
// 长了只读新长出来的那段；换了文件（滚动出新的 crossdesk.log）或被截短，从新文件开头读。
// 头一次只读末尾 initialWindow 字节：CrossDesk 启动那几句通常就在里面，读不到也只是不提示
import Foundation

package struct CrossDeskLogFollower: Sendable {
    package static let initialWindow: UInt64 = 1 << 20
    private var started = false
    private var file: UInt64?
    private var offset: UInt64 = 0
    /// 从文件中间开始读：读到的头一行是半截，丢到第一个换行为止
    private var skippingPartial = false
    /// 读到了一半的行（最后一个换行之后的字节）
    private var pending = Data()

    package init() {}

    /// file：文件的编号（inode），读不到为 nil；size：此刻的大小。返回这一拍要读的字节范围，没有新内容为 nil
    package mutating func range(file id: UInt64?, size: UInt64) -> Range<UInt64>? {
        if !started {
            started = true
            offset = size > Self.initialWindow ? size - Self.initialWindow : 0
            skippingPartial = offset > 0
        } else if id != file || size < offset {
            offset = 0
            skippingPartial = false
            pending = Data()
        }
        file = id
        return size > offset ? offset..<size : nil
    }

    /// 交回 range 那段读到的字节，返回新的完整的行
    package mutating func lines(from data: Data) -> [Substring] {
        offset += UInt64(data.count)
        var data = data[...]
        if skippingPartial {
            guard let newline = data.firstIndex(of: 0x0A) else { return [] }
            data = data[(newline + 1)...]
            skippingPartial = false
        }
        pending += data
        guard let last = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[..<last]
        pending = Data(pending[(last + 1)...])
        return String(decoding: complete, as: UTF8.self).split(separator: "\n")
    }
}
