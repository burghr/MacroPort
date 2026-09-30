import Foundation

/// A Windows 8BitDo macro file (.ini).
///
/// The file is not text. It is a binary dump of the same structure that the
/// macOS app keeps as JSON. All values are little endian.
///
/// Header, 12 bytes. The names come from the Windows UI:
///
///     0   u16   uniformMs    the value next to "Use uniform interval time"
///     2   u16   uniformOn    the checkbox for that value, 0 means off
///     4   u32   cyclesNum    0xFFFFFFFF means "Repeated"
///     8   u32   intervalMs   the "Interval" field, the gap between repeats
///
/// Step, 10 bytes, one for each macro step:
///
///     0   u16   msTimes        hold time in milliseconds
///     2   u16   keys           button bitmask
///     4   u16   triggerValue
///     6   u16   leftJoy        low byte X, high byte Y, 0x7F is centre
///     8   u16   rightJoy
///
/// The step list ends at the first step whose ten bytes are all zero.
struct MacroFile {
    static let headerLength = 12
    static let stepLength = 10

    var uniformMs: UInt16
    var uniformOn: Bool
    var cyclesNum: UInt32
    var intervalMs: UInt32
    var steps: [Step]
    var slots: Int

    struct Step: Equatable {
        var msTimes: UInt16
        var keys: UInt16
        var triggerValue: UInt16
        var leftJoy: UInt16
        var rightJoy: UInt16
    }

    var repeatsForever: Bool { cyclesNum == 0xFFFF_FFFF }
    var totalMs: Int { steps.reduce(0) { $0 + Int($1.msTimes) } }

    init(data: Data, label: String) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerLength + Self.stepLength else {
            throw MacroError.tooShort(label)
        }
        func u16(_ at: Int) -> UInt16 {
            UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
        }
        func u32(_ at: Int) -> UInt32 {
            UInt32(u16(at)) | UInt32(u16(at + 2)) << 16
        }

        uniformMs = u16(0)
        uniformOn = u16(2) != 0
        cyclesNum = u32(4)
        intervalMs = u32(8)
        slots = (bytes.count - Self.headerLength) / Self.stepLength

        var found: [Step] = []
        var at = Self.headerLength
        while at + Self.stepLength <= bytes.count {
            let block = bytes[at ..< at + Self.stepLength]
            if block.allSatisfy({ $0 == 0 }) { break }
            found.append(Step(msTimes: u16(at), keys: u16(at + 2),
                              triggerValue: u16(at + 4),
                              leftJoy: u16(at + 6), rightJoy: u16(at + 8)))
            at += Self.stepLength
        }
        guard !found.isEmpty else { throw MacroError.noSteps(label) }
        steps = found
    }
}

/// The button names. Three bits are confirmed against the Windows UI. The
/// other bits are unknown, so the code shows them as hex. The mask itself is
/// copied without change, so an unknown name never affects an import.
enum Buttons {
    static let names: [UInt16: String] = [0x0400: "L", 0x1000: "B", 0x2000: "A"]

    static func describe(_ mask: UInt16) -> String {
        if mask == 0 { return "release" }
        var parts: [String] = []
        for bit in 0 ..< 16 {
            let value = UInt16(1) << bit
            if mask & value != 0 {
                parts.append(names[value] ?? String(format: "0x%04x", value))
            }
        }
        return parts.joined(separator: "+")
    }

    static func describeStick(_ value: UInt16) -> String {
        let x = UInt8(value & 0xFF), y = UInt8(value >> 8)
        if x == 0x7F && y == 0x7F { return "centre" }
        var parts: [String] = []
        if x < 0x7F { parts.append("left") } else if x > 0x7F { parts.append("right") }
        if y < 0x7F { parts.append("up") } else if y > 0x7F { parts.append("down") }
        return parts.isEmpty ? "centre" : parts.joined(separator: "+")
    }
}

/// One step, in the form that the table shows.
struct StepRow: Identifiable {
    let id: Int
    let ms: UInt16
    let buttons: String
    let left: String
    let right: String
    let trigger: UInt16

    static func rows(for steps: [MacroFile.Step]) -> [StepRow] {
        steps.enumerated().map { index, step in
            StepRow(id: index + 1, ms: step.msTimes,
                    buttons: Buttons.describe(step.keys),
                    left: Buttons.describeStick(step.leftJoy),
                    right: Buttons.describeStick(step.rightJoy),
                    trigger: step.triggerValue)
        }
    }
}
