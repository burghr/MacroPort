import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: Model
    @State private var isTargeted = false

    private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var hasBanner: Bool { model.blockReason != nil || model.notice != nil }

    var body: some View {
        // HSplitView, not NavigationSplitView. A NavigationSplitView takes the
        // whole window on macOS, which pushed the banner past the bottom edge.
        VStack(spacing: 0) {
            HSplitView {
                Sidebar(isTargeted: $isTargeted)
                    .frame(minWidth: 250, idealWidth: 290, maxWidth: 400)
                Preview()
                    .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            if hasBanner {
                Divider()
                banners
            }
        }
        .toolbar { toolbar }
        .onReceive(clock) { _ in model.refresh() }
        .onAppear { model.refresh() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Label(model.appRunning ? "8BitDo app is open" : "8BitDo app is closed",
                  systemImage: model.appRunning ? "exclamationmark.triangle.fill"
                                                : "checkmark.circle.fill")
                .foregroundStyle(model.appRunning ? .orange : .green)
                .labelStyle(.titleAndIcon)
        }
        ToolbarItem { Spacer() }
        ToolbarItem {
            Picker("Profile", selection: $model.selectedKey) {
                ForEach(model.keys.keys.sorted(), id: \.self) { Text($0).tag($0) }
            }
            .frame(minWidth: 150)
        }
        ToolbarItem {
            Toggle("Replace same name", isOn: $model.replace)
        }
        ToolbarItem {
            Button("Import") { model.runImport() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canImport)
        }
    }

    private var banners: some View {
        VStack(spacing: 8) {
            if let reason = model.blockReason {
                Banner(text: reason, tint: .orange, icon: "exclamationmark.triangle.fill")
            }
            if let notice = model.notice {
                Banner(text: notice.text,
                       tint: notice.isError ? .red : .green,
                       icon: notice.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Banner: View {
    let text: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.4)))
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: Model
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dropZone
            List(selection: $model.selection) {
                if !model.files.isEmpty {
                    Section("To import") {
                        ForEach(model.files) { file in
                            fileRow(file).tag(PreviewTarget.file(file.id))
                        }
                    }
                }
                Section("Already in \(model.selectedKey)") {
                    if model.held.isEmpty {
                        Text("none").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(model.held) { macro in
                            storedRow(macro).tag(PreviewTarget.stored(macro.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            footer
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            receive(providers)
            return true
        }
    }

    private var dropZone: some View {
        Button { model.chooseFiles() } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc").font(.title2)
                Text("Drop .ini files here").fontWeight(.medium)
                Text("or click to choose").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .padding(12)
    }

    private func fileRow(_ file: LoadedFile) -> some View {
        HStack(spacing: 8) {
            label(file.name,
                  detail: file.macro.map { "\($0.steps.count) steps" } ?? (file.error ?? ""),
                  bad: !file.isReadable)
            Button {
                model.remove(file.id)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove this file")
        }
        .padding(.vertical, 2)
    }

    private func storedRow(_ macro: StoredMacro) -> some View {
        let repeats = macro.repeatsForever ? "repeats" : "\(macro.cyclesNum)x"
        return label(macro.name.isEmpty ? "(no name)" : macro.name,
                     detail: "\(macro.steps.count) steps, \(repeats)", bad: false)
            .padding(.vertical, 2)
    }

    private func label(_ title: String, detail: String, bad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(bad ? Color.red : Color.primary)
                .lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(model.selectedKey) holds \(model.held.count) of "
                 + "\(Preferences.maxMacros) macros")
                .fontWeight(.medium)
            Text(model.files.isEmpty ? "Drop files to import more."
                                     : "\(model.readable.count) file(s) ready to import.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.add(urls: [url]) }
            }
        }
    }
}

private struct Preview: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        if let summary = model.summary {
            VStack(alignment: .leading, spacing: 0) {
                facts(summary).padding(14)
                Divider()
                Table(summary.rows) {
                    TableColumn("#") { Text("\($0.id)").foregroundStyle(.secondary) }
                        .width(30)
                    TableColumn("ms") { Text("\($0.ms)") }.width(56)
                    TableColumn("Buttons") { row in
                        Text(row.buttons)
                            .fontWeight(row.buttons == "release" ? .regular : .semibold)
                            .foregroundStyle(row.buttons == "release" ? .secondary : .primary)
                    }
                    TableColumn("Left stick") { tint($0.left) }
                    TableColumn("Right stick") { tint($0.right) }
                    TableColumn("Trigger") { row in
                        Text("\(row.trigger)")
                            .foregroundStyle(row.trigger == 0 ? .secondary : .primary)
                    }.width(60)
                }
            }
        } else if let file = model.selectedFile {
            message(file.error ?? "This file is not a macro.", isError: true)
        } else {
            message("Choose a macro to see its steps.", isError: false)
        }
    }

    private func tint(_ text: String) -> some View {
        Text(text).foregroundStyle(text == "centre" ? .secondary : .primary)
    }

    private func message(_ text: String, isError: Bool) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(isError ? .red : .secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func facts(_ summary: MacroSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(summary.name).font(.title3).fontWeight(.semibold)
                Text(summary.isStored ? "saved in \(model.selectedKey)" : "ready to import")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                fact("Steps", summary.slots.map { "\(summary.stepCount) of \($0) slots" }
                                ?? "\(summary.stepCount)")
                fact("Interval", "\(summary.intervalMs) ms between repeats")
                fact("Repeat", summary.repeatText)
                if let uniform = summary.uniform {
                    fact("Uniform time", uniform)
                }
                fact("Run time", String(format: "%.2f s for one pass",
                                        Double(summary.totalMs) / 1000))
            }
            .font(.callout)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
