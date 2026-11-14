import AppKit
import SwiftUI

/// Menu-bar only: no Dock icon, no main window. One popover, built once.
@main @MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    let model = Model()
    private var item: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let out = ProcessInfo.processInfo.environment["HEUCAT_SNAPSHOT"] { return snapshot(to: out) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "HEUCAT")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .semitransient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: RootView().environmentObject(model))
        DispatchQueue.main.async { self.show() }   // launched from Spotlight: open right away
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    @objc private func toggle() { popover.isShown ? popover.performClose(nil) : show() }

    private func show() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Task { await model.refresh() }
    }

    /// `HEUCAT_SNAPSHOT=out.png HEUCAT_TAB=Coffres HEUCAT.app/Contents/MacOS/HEUCAT`
    /// renders one tab offscreen and exits (docs screenshots, visual checks).
    private func snapshot(to path: String) {
        if let t = Model.Tab(rawValue: ProcessInfo.processInfo.environment["HEUCAT_TAB"] ?? "") { model.tab = t }
        let view = NSHostingView(rootView: RootView().environmentObject(model)
            .background(Color(white: 0.11)).environment(\.colorScheme, .dark))
        view.frame = NSRect(x: 0, y: 0, width: 390, height: 540)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        Task {
            await model.refresh()
            if model.tab == .vaults { await model.refreshBanks() }
            try? await Task.sleep(for: .seconds(1))
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
