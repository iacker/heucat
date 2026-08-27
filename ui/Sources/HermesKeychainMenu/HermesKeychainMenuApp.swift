import AppKit
import SwiftUI

@main
struct HermesKeychainMenuApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Hermes Keychain", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .task { await exportDiagnosticCaptureIfRequested() }
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Secret…") { model.showingAddSecret = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            Label("Hermes Keychain", systemImage: model.iconName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(model)
        }
    }

    @MainActor
    private func exportDiagnosticCaptureIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["HERMES_UI_CAPTURE_PATH"] else { return }
        try? await Task.sleep(for: .seconds(5))
        let diagnostic = "busy=\(model.isBusy) message=\(model.message) configured=\(model.status.configuredCount)"
        try? diagnostic.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
        let renderer = ImageRenderer(
            content: DiagnosticSnapshotView()
                .environmentObject(model)
                .frame(width: 1240, height: 760)
        )
        renderer.scale = 1.5
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
