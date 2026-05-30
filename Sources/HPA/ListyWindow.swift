import AppKit
import SwiftUI

// Manually-managed window for the OL/DL generator, mirroring
// SettingsWindowController (the SwiftUI Window scene is unreliable in a
// menu-bar-only / LSUIElement app).
final class ListyWindowController: NSWindowController {
    static let shared = ListyWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: ListyView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Objednávkové a dodávkové listy"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 620))
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
