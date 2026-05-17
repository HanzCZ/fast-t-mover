import Foundation
import UserNotifications
import AppKit

/// Posts macOS notifications under FastTMover's bundle ID.
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

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }

        prepareQueueFile()
        processQueue()        // pick up anything written while we weren't watching
        startWatching()
    }

    /// Post a notification directly (used by Runner.run after Run Now).
    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
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
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            post(title: parts[0], body: parts[1])
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
