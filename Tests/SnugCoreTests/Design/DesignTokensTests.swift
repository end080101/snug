import Foundation
import Testing

// 设计令牌只有一份：design/design-tokens.json。Swift 里用的常量（Sources/Snug/UI/DesignTokens.swift）由这里按它生成，
// 测试比对两边逐字一致：改了令牌没重新生成、或者手改了生成的文件，都过不了。
// 重新生成：SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests

@Suite("设计令牌 DesignTokens")
struct DesignTokensTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let json = root.appendingPathComponent("design/design-tokens.json")
    static let swift = root.appendingPathComponent("Sources/Snug/UI/DesignTokens.swift")

    @Test("DesignTokens.swift 和 design-tokens.json 一致")
    func generatedMatches() throws {
        let tokens = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Self.json)) as? [String: Any])
        let rendered = try TokenRenderer(tokens).render()
        if ProcessInfo.processInfo.environment["SNUG_WRITE_TOKENS"] == "1" {
            try rendered.write(to: Self.swift, atomically: true, encoding: .utf8)
        }
        let current = try String(contentsOf: Self.swift, encoding: .utf8)
        #expect(current == rendered, "令牌改了没重新生成：SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests")
    }
}

/// 把令牌翻成 Swift。只认这份文件里出现的几种形状，认不出的直接报错，不悄悄跳过
private struct TokenRenderer {
    struct Unknown: Error, CustomStringConvertible {
        let description: String
    }

    let tokens: [String: Any]
    let palette: [String: [String: Any]]

    init(_ tokens: [String: Any]) throws {
        self.tokens = tokens
        palette = (tokens["palette"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
    }

    func render() throws -> String {
        var out = """
        // 生成的，不要手改：改 design/design-tokens.json，再运行 SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests。
        // 带 system 的颜色用系统语义色；只有 light / dark 的按外观取（iOS 的分组背景色 macOS 上没有）
        import AppKit
        import SwiftUI

        """
        for (name, section) in [("MacTokens", "mac"), ("TouchTokens", "touch")] {
            let body = try require(tokens[section] as? [String: Any], section)
            out += "\nenum \(name) {\n"
            for key in body.keys.sorted() where key != "about" {
                out += try group(key, body[key]!, path: "\(section).\(key)")
            }
            out += "}\n"
        }
        let motion = try require(tokens["motion"] as? [String: Any], "motion")
        out += "\nenum MotionTokens {\n"
        for key in motion.keys.sorted() where key != "about" {
            let path = "motion.\(key)"
            if let value = motion[key] as? NSNumber {
                out += "    static let \(key): Double = \(number(value))\n"
            } else {
                let spec = try require(motion[key] as? [String: Any], path)
                let ms = try require(spec["duration"] as? NSNumber, path)
                out += "    /// \(spec["use"] as? String ?? "")\n"
                out += "    static let \(key): Double = \(number(NSNumber(value: ms.doubleValue / 1000)))\n"
            }
        }
        out += "}\n"
        return out
    }

    /// 一组令牌：字号、颜色、间距……按组名决定翻成什么
    private func group(_ key: String, _ value: Any, path: String) throws -> String {
        let items = try require(value as? [String: Any], path)
        let type = key.prefix(1).uppercased() + key.dropFirst()
        var out = "    enum \(type) {\n"
        for name in items.keys.sorted() where name != "about" && name != "family" {
            let item = items[name]!
            let at = "\(path).\(name)"
            switch key {
            case "color": out += "        static let \(name) = \(try color(item, at))\n"
            case "font": out += "        static let \(name) = \(try font(item, at))\n"
            case "iconTile", "status": out += "        \(try tile(name, item, at, status: key == "status"))\n"
            default: out += try measure(name, item, at, indent: "        ")
            }
        }
        return out + "    }\n"
    }

    private func measure(_ name: String, _ item: Any, _ path: String, indent: String) throws -> String {
        if let n = item as? NSNumber { return "\(indent)static let \(name): CGFloat = \(number(n))\n" }
        let fields = try require(item as? [String: Any], path)
        var out = "\(indent)enum \(name.prefix(1).uppercased() + name.dropFirst()) {\n"
        for field in fields.keys.sorted() where field != "note" {
            out += try measure(field, fields[field]!, "\(path).\(field)", indent: indent + "    ")
        }
        return out + "\(indent)}\n"
    }

    private func color(_ item: Any, _ path: String) throws -> String {
        let spec = try require(item as? [String: Any], path)
        if let ref = spec["ref"] as? String { return try paletteColor(ref, path) }
        // 系统语义色：是 NSColor 的名字就直接用，系统没有对应的（分组表单的底这类）按外观取
        if let system = spec["system"] as? String, system.range(of: "^[a-zA-Z]+Color$", options: .regularExpression) != nil {
            // 系统色加透明度（强调色的浅底）：跟着系统色走，深浅外观各一个透明度
            if let alpha = spec["alpha"] as? [String: Double] {
                let light = try require(alpha["light"], "\(path).alpha.light")
                let dark = try require(alpha["dark"], "\(path).alpha.dark")
                return "SwiftUI.Color(nsColor: .dynamic(light: .\(system).withAlphaComponent(\(number(NSNumber(value: light)))), "
                    + "dark: .\(system).withAlphaComponent(\(number(NSNumber(value: dark))))))"
            }
            return "SwiftUI.Color(nsColor: .\(system))"
        }
        let light = try require(spec["light"] as? String, "\(path).light")
        let dark = try require(spec["dark"] as? String, "\(path).dark")
        return "SwiftUI.Color(nsColor: .dynamic(light: \(try rgba(light, path)), dark: \(try rgba(dark, path))))"
    }

    private func paletteColor(_ ref: String, _ path: String) throws -> String {
        let name = String(ref.dropFirst("palette.".count))
        let system = try require(palette[name]?["system"] as? String, "\(path) → \(ref)")
        return "SwiftUI.Color(nsColor: .\(system))"
    }

    /// #RRGGBB 或 rgba(r,g,b,a)
    private func rgba(_ text: String, _ path: String) throws -> String {
        var c: [Double]
        if text.hasPrefix("#"), text.count == 7, let v = Int(text.dropFirst(), radix: 16) {
            c = [Double(v >> 16 & 0xFF), Double(v >> 8 & 0xFF), Double(v & 0xFF), 1]
        } else if text.hasPrefix("rgba(") {
            c = text.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            throw Unknown(description: "\(path)：认不出颜色 \(text)")
        }
        guard c.count == 4 else { throw Unknown(description: "\(path)：认不出颜色 \(text)") }
        func f(_ v: Double) -> String { number(NSNumber(value: (v * 1000).rounded() / 1000)) }
        return "NSColor(srgbRed: \(f(c[0] / 255)), green: \(f(c[1] / 255)), blue: \(f(c[2] / 255)), alpha: \(f(c[3])))"
    }

    private func font(_ item: Any, _ path: String) throws -> String {
        let spec = try require(item as? [String: Any], path)
        let size = try require(spec["size"] as? NSNumber, "\(path).size")
        let weight = try require(spec["weight"] as? NSNumber, "\(path).weight")
        let line = try require(spec["lineHeight"] as? NSNumber, "\(path).lineHeight")
        let names = [400: "regular", 500: "medium", 600: "semibold", 700: "bold"]
        let name = try require(names[weight.intValue], "\(path).weight")
        return "FontToken(size: \(number(size)), weight: .\(name), lineHeight: \(number(line)))"
    }

    /// 图标块：颜色加图标。没写 symbol 的只定颜色，翻成带 symbol 参数的函数，图标由用的地方按状态给
    private func tile(_ name: String, _ item: Any, _ path: String, status: Bool) throws -> String {
        let spec = try require(item as? [String: Any], path)
        let color = try paletteColor(try require(spec["ref"] as? String, "\(path).ref"), path)
        if !status, spec["symbol"] == nil {
            return "static func \(name)(symbol: String) -> TileToken { TileToken(color: \(color), symbol: symbol) }"
        }
        let symbol = try require(spec["symbol"] as? String, "\(path).symbol")
        guard status else { return "static let \(name) = TileToken(color: \(color), symbol: \"\(symbol)\")" }
        let text = try require(spec["text"] as? String, "\(path).text")
        return "static let \(name) = StatusToken(color: \(color), symbol: \"\(symbol)\", text: \"\(text)\")"
    }

    private func number(_ n: NSNumber) -> String {
        let d = n.doubleValue
        return d == d.rounded() && abs(d) < 1e9 ? String(Int(d)) : String(d)
    }

    private func require<T>(_ value: T?, _ path: String) throws -> T {
        guard let value else { throw Unknown(description: "\(path)：形状不对") }
        return value
    }
}
