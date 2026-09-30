import AppKit
import Foundation

enum MacroError: LocalizedError {
    case tooShort(String)
    case noSteps(String)
    case nameTooLong(String)
    case appRunning
    case missingPlist
    case duplicate(String, String)
    case full(String, Int)
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .tooShort(let name):
            return "The file is too short to hold a macro: \(name)"
        case .noSteps(let name):
            return "The file holds no macro steps: \(name)"
        case .nameTooLong(let name):
            return "The name is longer than \(Preferences.maxNameCharacters) characters: \(name)"
        case .appRunning:
            return "8BitDo Ultimate Software V2 is still running. Quit the app first, "
                 + "because the app overwrites its preferences when it exits."
        case .missingPlist:
            return "The preferences file does not exist. Start 8BitDo Ultimate Software V2 "
                 + "once, then quit it."
        case .duplicate(let name, let key):
            return "A macro named \(name) already exists in \(key). "
                 + "Turn on Replace to overwrite it."
        case .full(let key, let held):
            return "\(key) already holds \(held) macros, which is the limit. "
                 + "Delete one in the app first."
        case .nothingSelected:
            return "No macro was selected."
        }
    }
}

/// One macro that the app already holds.
struct StoredMacro: Identifiable, Equatable {
    var key: String
    var slot: Int
    var name: String
    var intervalMs: Int
    var cyclesNum: Int
    var steps: [MacroFile.Step]

    /// A stable id, so the selection survives a refresh.
    var id: String { "\(key)#\(slot)" }
    var repeatsForever: Bool { cyclesNum == 0xFFFF_FFFF }
    var totalMs: Int { steps.reduce(0) { $0 + Int($1.msTimes) } }
}

struct StoreResult {
    var backup: URL
    var key: String
    var count: Int
    var names: [String]
}

/// Reads and writes the macros in the sandbox preferences file of the
/// 8BitDo app. The tool writes only the macro list. It does not touch the
/// cache that matches the controller, which the app rebuilds when you press
/// "Load to Profile".
enum Preferences {
    static let bundleID = "com.8BitDo.UltimateV2"
    static let executableName = "8BitDo Ultimate Software V2"
    static let defaultKey = "Pro3Macro_0"
    static let defaultStepsKey = "pro3Datas"
    static let maxMacros = 4
    static let nameByteLength = 32
    static var maxNameCharacters: Int { nameByteLength / 2 }

    /// A test harness can point this at a copy.
    static var plistURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")

    static var backupDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/MacroPort/Backups")

    // MARK: - State

    /// True while the 8BitDo app runs. The check uses the bundle name as well
    /// as the bundle id, because macOS moves a quarantined app to a random
    /// path before it starts it.
    static func appIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if app.bundleIdentifier == bundleID { return true }
            if let path = app.executableURL?.path, path.contains(executableName) { return true }
            return false
        }
    }

    static func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw MacroError.missingPlist
        }
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any]
        return plist ?? [:]
    }

    /// True for a key such as Pro3Macro_0, where the number is the profile.
    static func isMacroKey(_ key: String) -> Bool {
        guard let range = key.range(of: "Macro_", options: .backwards) else { return false }
        let device = key[key.startIndex ..< range.lowerBound]
        let profile = key[range.upperBound...]
        return !device.isEmpty && device.allSatisfy { $0.isLetter || $0.isNumber }
            && !profile.isEmpty && profile.allSatisfy(\.isNumber)
    }

    /// Every key that holds macros, such as Pro3Macro_0.
    static func macroKeys(in plist: [String: Any]) -> [String] {
        var keys = plist.keys.filter(isMacroKey).sorted()
        if !keys.contains(defaultKey) { keys.append(defaultKey) }
        return keys
    }

    static func entries(in plist: [String: Any], key: String) -> [[String: Any]] {
        guard let data = plist[key] as? Data,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list
    }

    /// Each device uses its own name for the step array. Reuse what is there.
    static func stepsKey(of entries: [[String: Any]]) -> String {
        for entry in entries {
            for name in entry.keys where name.hasSuffix("Datas") { return name }
        }
        return defaultStepsKey
    }

    static func survey() throws -> [String: [StoredMacro]] {
        let plist = try load()
        var result: [String: [StoredMacro]] = [:]
        for key in macroKeys(in: plist) {
            let list = entries(in: plist, key: key)
            let stepsKey = stepsKey(of: list)
            result[key] = list.enumerated().map { slot, entry in
                let model = entry["model"] as? [String: Any] ?? [:]
                let raw = entry[stepsKey] as? [[String: Any]] ?? []
                return StoredMacro(
                    key: key, slot: slot,
                    name: decodeName(model["name"] as? [Int] ?? []),
                    intervalMs: model["intervalMs"] as? Int ?? 0,
                    cyclesNum: model["cyclesNum"] as? Int ?? 0,
                    steps: raw.map(step(from:)))
            }
        }
        return result
    }

    /// Read back one step of a macro that the app already holds.
    static func step(from dict: [String: Any]) -> MacroFile.Step {
        func value(_ name: String) -> UInt16 {
            UInt16(truncatingIfNeeded: dict[name] as? Int ?? 0)
        }
        return MacroFile.Step(msTimes: value("msTimes"), keys: value("keys"),
                              triggerValue: value("triggerValue"),
                              leftJoy: value("leftJoy"), rightJoy: value("rightJoy"))
    }

    // MARK: - Names

    /// The app stores a name as 32 bytes of UTF-16, big endian, zero padded.
    static func encodeName(_ text: String) throws -> [Int] {
        var bytes: [UInt8] = []
        for unit in Array(text.utf16) {
            bytes.append(UInt8(unit >> 8))
            bytes.append(UInt8(unit & 0xFF))
        }
        guard bytes.count <= nameByteLength else { throw MacroError.nameTooLong(text) }
        bytes.append(contentsOf: [UInt8](repeating: 0, count: nameByteLength - bytes.count))
        return bytes.map(Int.init)
    }

    static func decodeName(_ array: [Int]) -> String {
        var units: [UInt16] = []
        var index = 0
        while index + 1 < array.count {
            let unit = UInt16(array[index] & 0xFF) << 8 | UInt16(array[index + 1] & 0xFF)
            if unit == 0 { break }
            units.append(unit)
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - Writing

    static func entry(name: String, macro: MacroFile, stepsKey: String) throws -> [String: Any] {
        // The app fills maxSteps, keyMap, and offset when you load the macro
        // to the profile. Keep them at 0 here.
        let model: [String: Any] = [
            "name": try encodeName(name),
            "keyMap": 0, "placehold1": 0, "placehold2": 0, "specialFlag": 0,
            "maxSteps": 0, "gamepadMode": 0, "offset": 0,
            "cyclesNum": Int(macro.cyclesNum),
            "intervalMs": Int(macro.intervalMs),
        ]
        let steps: [[String: Any]] = macro.steps.map {
            ["msTimes": Int($0.msTimes), "keys": Int($0.keys),
             "triggerValue": Int($0.triggerValue),
             "leftJoy": Int($0.leftJoy), "rightJoy": Int($0.rightJoy)]
        }
        return ["model": model, stepsKey: steps, "isActive": false]
    }

    /// Write the macros in one step. A problem with any macro leaves the
    /// preferences file untouched.
    @discardableResult
    static func store(macros: [(name: String, macro: MacroFile)],
                      key: String, replace: Bool) throws -> StoreResult {
        guard !macros.isEmpty else { throw MacroError.nothingSelected }
        guard !appIsRunning() else { throw MacroError.appRunning }

        var plist = try load()
        var list = entries(in: plist, key: key)
        let stepsKey = stepsKey(of: list)

        for item in macros {
            let matches = list.indices.filter { index in
                let model = list[index]["model"] as? [String: Any] ?? [:]
                return decodeName(model["name"] as? [Int] ?? []) == item.name
            }
            if !matches.isEmpty && !replace {
                throw MacroError.duplicate(item.name, key)
            }
            for index in matches.reversed() { list.remove(at: index) }
            guard list.count < maxMacros else { throw MacroError.full(key, list.count) }
            list.append(try entry(name: item.name, macro: item.macro, stepsKey: stepsKey))
        }

        let backup = try backupPlist()
        plist[key] = try JSONSerialization.data(withJSONObject: list)
        let output = try PropertyListSerialization
            .data(fromPropertyList: plist, format: .binary, options: 0)
        try output.write(to: plistURL)
        resetPreferencesCache()

        return StoreResult(backup: backup, key: key, count: list.count,
                           names: macros.map(\.name))
    }

    static func backupPlist() throws -> URL {
        try FileManager.default.createDirectory(at: backupDirectory,
                                                withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: .current, calendar: .current))
        let target = backupDirectory.appending(path: "\(bundleID).plist.backup-\(stamp)")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: plistURL, to: target)
        return target
    }

    /// macOS caches preferences. Drop the cache so the app reads the new file.
    static func resetPreferencesCache() {
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/killall")
        task.arguments = ["cfprefsd"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
