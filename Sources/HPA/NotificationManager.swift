import Foundation
import UserNotifications
import AppKit

enum NotificationKind: String {
    case success, failure, info

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .success: return .systemGreen
        case .failure: return .systemRed
        case .info:    return .systemBlue
        }
    }
}

/// Posts macOS notifications under HPA's bundle ID.
/// Watches a queue file written to by the worker script (so LaunchAgent
/// runs can deliver notifications even though they don't go through the
/// menu-bar app's Runner code path).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var watchSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    var queueFile: String {
        "\(NSHomeDirectory())/.local/state/fast_t_mover/notify.queue"
    }

    var iconDir: String {
        "\(NSHomeDirectory())/.local/state/fast_t_mover/icons"
    }

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }

        renderIcons()
        prepareQueueFile()
        processQueue()        // pick up anything written while we weren't watching
        startWatching()
    }

    /// Post a notification directly (used by Runner.run after Run Now).
    func post(title: String, body: String, kind: NotificationKind = .info) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        if let url = iconURL(for: kind),
           let attachment = try? UNNotificationAttachment(
                identifier: kind.rawValue, url: url, options: nil
           ) {
            content.attachments = [attachment]
        }

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Icon rendering

    private func iconURL(for kind: NotificationKind) -> URL? {
        let path = "\(iconDir)/\(kind.rawValue).png"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Render SF Symbols once per launch into the state dir so they can be
    /// attached to UNNotifications (which require an on-disk URL).
    private func renderIcons() {
        try? FileManager.default.createDirectory(
            atPath: iconDir, withIntermediateDirectories: true)
        for kind in [NotificationKind.success, .failure, .info] {
            let dest = "\(iconDir)/\(kind.rawValue).png"
            if let data = renderSymbolPNG(name: kind.symbolName,
                                          color: kind.tint, size: 256) {
                try? data.write(to: URL(fileURLWithPath: dest))
            }
        }
    }

    private func renderSymbolPNG(name: String, color: NSColor, size: CGFloat) -> Data? {
        // Hierarchical = primary glyph in full color, secondary (background fill)
        // automatically tinted lighter. Produces a recognisable check/cross
        // shape rather than a flat coloured blob.
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        else { return nil }

        let dim = Int(size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dim, pixelsHigh: dim,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let symSize = symbol.size
        let scale = min(rect.width / symSize.width, rect.height / symSize.height) * 0.9
        let drawW = symSize.width * scale
        let drawH = symSize.height * scale
        let drawRect = NSRect(
            x: (rect.width  - drawW) / 2,
            y: (rect.height - drawH) / 2,
            width: drawW, height: drawH
        )
        symbol.draw(in: drawRect)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Queue file plumbing

    private func prepareQueueFile() {
        let dir = (queueFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: queueFile) {
            FileManager.default.createFile(atPath: queueFile, contents: nil)
        }
    }

    private func startWatching() {
        fd = open(queueFile, O_EVTONLY)
        guard fd != -1 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd != -1 { close(fd) }
            self?.fd = -1
        }
        source.resume()
        watchSource = source
    }

    private func handleEvent() {
        let event = watchSource?.data ?? []
        if event.contains(.delete) || event.contains(.rename) {
            // File replaced (e.g. our own truncate via atomic write).
            // Re-open and re-watch.
            watchSource?.cancel()
            prepareQueueFile()
            startWatching()
            processQueue()
            return
        }
        processQueue()
    }

    private func processQueue() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: queueFile)),
              !data.isEmpty,
              let text = String(data: data, encoding: .utf8)
        else { return }

        // Truncate first to minimise the race window where the script appends
        // while we're posting. Any line written after this read is lost.
        // Worker writes notifications atomically per line so the race is tiny.
        try? "".write(toFile: queueFile, atomically: false, encoding: .utf8)

        // If the app was off for a while, just show the most recent ones —
        // don't carpet-bomb the user with stale banners.
        let lines = text.split(separator: "\n").map(String.init)
        let recent = lines.suffix(3)
        for line in recent {
            // New format: "kind|title|body". Tolerate the old "title|body".
            let parts = line.split(separator: "|", maxSplits: 2,
                                   omittingEmptySubsequences: false).map(String.init)
            switch parts.count {
            case 3:
                let kind = NotificationKind(rawValue: parts[0]) ?? .info
                post(title: parts[1], body: parts[2], kind: kind)
            case 2:
                post(title: parts[0], body: parts[1], kind: .info)
            default:
                continue
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when our app is frontmost.
        completionHandler([.banner, .sound])
    }
}
