import AppKit
import SwiftUI

final class FakturoidWindowController: NSWindowController {
    static let shared = FakturoidWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: FakturoidView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "HPA — Fakturoid"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 560))
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
