import AppKit
import SwiftUI

// Manually-managed window for the Asana helpdesk-blocker bulk creator,
// matching the SettingsWindowController / ListyWindowController pattern.
final class AsanaWindowController: NSWindowController {
    static let shared = AsanaWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: AsanaView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "HPA — Asana"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 560))
        window.center()
        self.init(window: window)
    }

    func show(mode: AsanaUIState.Mode = .blockers) {
        AsanaUIState.shared.mode = mode
        // Re-evaluate the date-based sprint each time the window opens.
        AsanaBlockerSettings.shared.selectSprintForToday()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
