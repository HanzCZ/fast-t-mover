import AppKit
import SwiftUI

/// Manually-managed settings window. The SwiftUI `Settings` scene plus
/// `showSettingsWindow:` is unreliable in LSUIElement (menu-bar-only) apps
/// because there is no main menu to route the action through.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "HPA — Nastavení"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 640))
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
