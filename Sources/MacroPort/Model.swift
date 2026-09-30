import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// One file that the user dropped on the window.
struct LoadedFile: Identifiable {
    let id = UUID()
    var name: String
    var url: URL
    var macro: MacroFile?
    var error: String?

    var isReadable: Bool { macro != nil }
}

/// What the preview pane shows: a file to import, or a macro the app holds.
enum PreviewTarget: Hashable {
    case file(UUID)
    case stored(String)
}

/// One macro in the form that the preview pane draws, from either source.
struct MacroSummary {
    var name: String
    var stepCount: Int
    var slots: Int?          // nil for a macro that the app already holds
    var intervalMs: Int
    var cyclesNum: Int
    var uniform: String?     // nil, because the app does not store the setting
    var totalMs: Int
    var rows: [StepRow]
    var isStored: Bool

    var repeatText: String {
        cyclesNum == 0xFFFF_FFFF ? "Repeated (forever)" : "\(cyclesNum) time(s)"
    }
}

struct Notice: Identifiable {
    let id = UUID()
    var text: String
    var isError: Bool
}

@MainActor
final class Model: ObservableObject {
    @Published var files: [LoadedFile] = []
    @Published var selection: PreviewTarget?
    @Published var keys: [String: [StoredMacro]] = [:]
    @Published var selectedKey = Preferences.defaultKey
    @Published var replace = false
    @Published var appRunning = false
    @Published var notice: Notice?

    var selectedFile: LoadedFile? {
        guard case .file(let id) = selection else { return nil }
        return files.first { $0.id == id }
    }

    var selectedStored: StoredMacro? {
        guard case .stored(let id) = selection else { return nil }
        return held.first { $0.id == id }
    }

    /// The macro that the preview pane draws, whichever row is selected.
    var summary: MacroSummary? {
        if let file = selectedFile, let macro = file.macro {
            return MacroSummary(
                name: file.name, stepCount: macro.steps.count, slots: macro.slots,
                intervalMs: Int(macro.intervalMs), cyclesNum: Int(macro.cyclesNum),
                uniform: "\(macro.uniformOn ? "on" : "off"), \(macro.uniformMs) ms",
                totalMs: macro.totalMs, rows: StepRow.rows(for: macro.steps),
                isStored: false)
        }
        if let stored = selectedStored {
            return MacroSummary(
                name: stored.name, stepCount: stored.steps.count, slots: nil,
                intervalMs: stored.intervalMs, cyclesNum: stored.cyclesNum,
                uniform: nil, totalMs: stored.totalMs,
                rows: StepRow.rows(for: stored.steps), isStored: true)
        }
        return nil
    }

    var readable: [LoadedFile] { files.filter(\.isReadable) }

    var held: [StoredMacro] { keys[selectedKey] ?? [] }

    var clashes: [String] {
        let names = Set(held.map(\.name))
        return readable.map(\.name).filter(names.contains)
    }

    /// How many macros the profile would hold after an import.
    var projectedCount: Int {
        let names = Set(held.map(\.name))
        let added = readable.map(\.name).filter { !(replace && names.contains($0)) }
        return held.count + added.count
    }

    /// The reason that the Import button is off, or nil when it is on.
    var blockReason: String? {
        if appRunning {
            return "Quit 8BitDo Ultimate Software V2 before you import. "
                 + "The app overwrites its preferences when it exits."
        }
        if readable.isEmpty { return nil }
        if projectedCount > Preferences.maxMacros {
            return "\(readable.count) file(s) would make \(projectedCount) macros. "
                 + "The limit is \(Preferences.maxMacros). Remove "
                 + "\(projectedCount - Preferences.maxMacros) file(s), or delete a macro "
                 + "in the app first."
        }
        if !clashes.isEmpty && !replace {
            return "\(clashes.joined(separator: ", ")) already exists. "
                 + "Turn on Replace to overwrite it."
        }
        if let long = readable.first(where: { $0.name.count > Preferences.maxNameCharacters }) {
            return "The name \(long.name) is longer than "
                 + "\(Preferences.maxNameCharacters) characters. Rename the file."
        }
        return nil
    }

    var canImport: Bool { !readable.isEmpty && blockReason == nil }

    // MARK: - Actions

    func refresh() {
        appRunning = Preferences.appIsRunning()
        do {
            let found = try Preferences.survey()
            if found != keys { keys = found }
            if keys[selectedKey] == nil, let first = keys.keys.sorted().first {
                selectedKey = first
            }
        } catch {
            keys = [:]
            notice = Notice(text: error.localizedDescription, isError: true)
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ini") ?? .data]
        panel.message = "Choose the Windows macro files to import."
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func add(urls: [URL]) {
        notice = nil
        for url in urls where url.pathExtension.lowercased() == "ini" {
            let name = url.deletingPathExtension().lastPathComponent
            var loaded = LoadedFile(name: name, url: url)
            do {
                loaded.macro = try MacroFile(data: try Data(contentsOf: url), label: name)
            } catch {
                loaded.error = error.localizedDescription
            }
            if let at = files.firstIndex(where: { $0.name == name }) {
                let old = files[at].id
                files[at] = loaded
                if selection == .file(old) { selection = .file(loaded.id) }
            } else {
                files.append(loaded)
            }
        }
        if selection == nil, let first = files.first { selection = .file(first.id) }
    }

    func remove(_ id: LoadedFile.ID) {
        files.removeAll { $0.id == id }
        if selection == .file(id) {
            selection = files.first.map { PreviewTarget.file($0.id) }
        }
    }

    func removeAll() {
        files.removeAll()
        if case .file = selection { selection = nil }
    }

    func runImport() {
        notice = nil
        let macros = readable.compactMap { file -> (name: String, macro: MacroFile)? in
            guard let macro = file.macro else { return nil }
            return (file.name, macro)
        }
        do {
            let result = try Preferences.store(macros: macros, key: selectedKey,
                                               replace: replace)
            notice = Notice(
                text: "Imported \(result.names.joined(separator: ", ")). "
                    + "\(result.key) now holds \(result.count) macros. Start the app, "
                    + "open the Macro screen, then press Load to Profile.",
                isError: false)
            removeAll()
        } catch {
            notice = Notice(text: error.localizedDescription, isError: true)
        }
        refresh()
    }

    func showBackups() {
        try? FileManager.default.createDirectory(at: Preferences.backupDirectory,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(Preferences.backupDirectory)
    }
}
