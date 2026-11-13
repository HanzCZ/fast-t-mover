import Foundation
import AppKit

/// Runs the mover on a schedule from inside the app: at launch, on wake and
/// every 15 minutes; the script's own interval gate decides whether a tick
/// does any work.
///
/// This replaces the old launchd agent. A script started by launchd runs
/// outside the app's privacy grants, so macOS refused it the Downloads
/// folder and it reported "nothing to move" while files were waiting. Runs
/// started from here inherit the app's folder access, same as "Move Files".
final class MoverScheduler {
    static let shared = MoverScheduler()
    static let enabledKey = "autoRunEnabled"
    private static let tick: TimeInterval = 900

    private let queue = DispatchQueue(label: "com.hanak.hpa.mover", qos: .utility)
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    /// Call once at launch: migrates the old launchd agent and starts the
    /// schedule when auto-run is on.
    func bootstrap() {
        let d = UserDefaults.standard
        if FileManager.default.fileExists(atPath: LaunchAgent.plistPath) {
            // The agent existing means auto-run was on; keep it on, in-app.
            LaunchAgent.uninstall()
            d.set(true, forKey: Self.enabledKey)
        }
        apply(enabled: d.bool(forKey: Self.enabledKey))
    }

    func apply(enabled: Bool) {
        timer?.invalidate(); timer = nil
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            wakeObserver = nil
        }
        guard enabled else { return }

        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.runNow() }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Give Wi-Fi a moment to reassociate before the script tries SMB.
            self?.queue.asyncAfter(deadline: .now() + 20) { _ = Runner.run() }
        }
        runNow()
    }

    private func runNow() {
        queue.async { _ = Runner.run() }
    }
}
