import SwiftUI

@main
struct MacroPortApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("MacroPort") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .importExport) {
                Button("Add Macro Files…") { model.chooseFiles() }
                    .keyboardShortcut("o")
                Button("Show Backups in Finder") { model.showBackups() }
            }
        }
    }
}
