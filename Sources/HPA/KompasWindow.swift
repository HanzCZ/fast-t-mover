import AppKit
import SwiftUI

// Manually-managed window for the Kompas task generators,
// matching the SettingsWindowController / ListyWindowController pattern.
final class KompasWindowController: NSWindowController {
    static let shared = KompasWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: KompasView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "HPA — Kompas"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 560))
        window.center()
        self.init(window: window)
    }

    func show(mode: KompasUIState.Mode = .blockers) {
        KompasUIState.shared.mode = mode
        // Re-evaluate the date-based sprint each time the window opens.
        KompasTaskSettings.shared.selectSprintForToday()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
