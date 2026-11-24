// 只听不改：记录 CrossDesk 注入的鼠标事件（kCGEventSourceUserData == "CROSSDES"），本机触控板、鼠标不记
import CoreGraphics
import Foundation

let marker: Int64 = 0x43524f5353444553
let start = Date()
setvbuf(stdout, nil, _IOLBF, 0)

let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

let names: [UInt32: String] = [
    CGEventType.mouseMoved.rawValue: "move", CGEventType.leftMouseDown.rawValue: "Ldown",
    CGEventType.leftMouseUp.rawValue: "Lup", CGEventType.leftMouseDragged.rawValue: "Ldrag",
    CGEventType.rightMouseDown.rawValue: "Rdown", CGEventType.rightMouseUp.rawValue: "Rup",
    CGEventType.rightMouseDragged.rawValue: "Rdrag", CGEventType.otherMouseDown.rawValue: "Odown",
    CGEventType.otherMouseUp.rawValue: "Oup", CGEventType.otherMouseDragged.rawValue: "Odrag",
    CGEventType.scrollWheel.rawValue: "scroll",
]

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        print("tap disabled: \(type.rawValue)")
        return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUserData) == marker else { return Unmanaged.passUnretained(event) }
    let t = String(format: "%9.3f", Date().timeIntervalSince(start))
    let p = event.location
    var line = "\(t) \(names[type.rawValue] ?? "t\(type.rawValue)") (\(Int(p.x)),\(Int(p.y)))"
    if type == .scrollWheel {
        line += " lines=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),\(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))"
        line += " px=\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))"
        line += " continuous=\(event.getIntegerValueField(.scrollWheelEventIsContinuous))"
        line += " phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))"
    } else if type != .mouseMoved {
        line += " clicks=\(event.getIntegerValueField(.mouseEventClickState))"
    }
    line += " pid=\(event.getIntegerValueField(.eventSourceUnixProcessID))"
    line += " ts=\(event.timestamp)"
    print(line)
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                  eventsOfInterest: mask, callback: callback, userInfo: nil) else {
    print("建不起事件监听（没有权限）")
    exit(2)
}
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("listening")
let limit = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 600 : 600
DispatchQueue.main.asyncAfter(deadline: .now() + limit) { print("time limit"); exit(0) }
CFRunLoopRun()
