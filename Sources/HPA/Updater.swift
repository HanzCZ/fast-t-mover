import Foundation
import AppKit

// Self-update from GitHub Releases. The repo is public, so the Releases API
// is reachable anonymously. We download the release's .zip asset via
// URLSession (which — unlike a browser download — does NOT set the
// com.apple.quarantine flag), unzip it, swap the bundle in /Applications, and
// relaunch. Because the bundle keeps its ad-hoc signature and gains no
// quarantine xattr, Gatekeeper stays quiet despite no notarization.
enum Updater {
    static let repo = "HanzCZ/fast-t-mover"
    static let installedAppPath = "/Applications/HPA.app"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    struct Release {
        let version: String
        let zipURL: URL
        let htmlURL: URL
        let notes: String
    }

    enum CheckResult {
        case upToDate(current: String)
        case available(Release)
        case error(String)
    }

    // MARK: - Check

    static func checkLatest(_ completion: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return onMain(completion, .error("Neplatná URL."))
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("HPA-Updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err { return onMain(completion, .error(err.localizedDescription)) }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                return onMain(completion, .error("Nečekaná odpověď GitHubu."))
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let html = (obj["html_url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://github.com/\(repo)/releases/latest")!
            let notes = (obj["body"] as? String) ?? ""
            let zip = (obj["assets"] as? [[String: Any]] ?? []).compactMap { a -> URL? in
                guard let name = a["name"] as? String, name.hasSuffix(".zip"),
                      let s = a["browser_download_url"] as? String else { return nil }
                return URL(string: s)
            }.first

            if compare(latest, currentVersion) <= 0 {
                return onMain(completion, .upToDate(current: currentVersion))
            }
            guard let zip else {
                return onMain(completion, .error("Release \(tag) nemá .zip přílohu pro automatickou aktualizaci."))
            }
            onMain(completion, .available(Release(version: latest, zipURL: zip, htmlURL: html, notes: notes)))
        }.resume()
    }

    // Semantic version compare: <0 if a<b, 0 if equal, >0 if a>b.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    // MARK: - Install

    static func downloadAndInstall(_ release: Release, failure: @escaping (String) -> Void) {
        URLSession.shared.downloadTask(with: release.zipURL) { tmp, _, err in
            if let err { return onMain(failure, err.localizedDescription) }
            guard let tmp else { return onMain(failure, "Stažení selhalo.") }
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("hpa_update_\(UUID().uuidString)")
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("update.zip")
                try fm.moveItem(at: tmp, to: zip)

                let unzipped = work.appendingPathComponent("unzipped")
                let status = try run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path])
                guard status == 0 else { return onMain(failure, "Rozbalení archivu selhalo.") }

                guard let app = findApp(in: unzipped) else {
                    return onMain(failure, "V archivu nebyla nalezena HPA.app.")
                }
                swapAndRelaunch(newApp: app)
            } catch {
                onMain(failure, error.localizedDescription)
            }
        }.resume()
    }

    private static func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for it in items where it.pathExtension == "app" { return it }
        for it in items {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: it.path, isDirectory: &isDir), isDir.boolValue,
               let found = findApp(in: it) { return found }
        }
        return nil
    }

    // Hand the swap to a detached shell that waits for us to quit, replaces the
    // bundle, and relaunches it. Done in shell because we can't overwrite our
    // own running bundle from within the process cleanly.
    private static func swapAndRelaunch(newApp: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(installedAppPath)"
        cp -R "\(newApp.path)" "\(installedAppPath)"
        xattr -dr com.apple.quarantine "\(installedAppPath)" 2>/dev/null
        open "\(installedAppPath)"
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hpa_swap_\(UUID().uuidString).sh")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = [url.path]
        try? p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    @discardableResult
    private static func run(_ launch: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.launchPath = launch
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func onMain<T>(_ c: @escaping (T) -> Void, _ v: T) {
        DispatchQueue.main.async { c(v) }
    }
}

// User-facing flow via NSAlert (works from the menu-bar-only app).
enum UpdaterUI {
    static func checkInteractive() {
        Updater.checkLatest { result in
            switch result {
            case .upToDate(let cur):
                alert("Máš nejnovější verzi", "HPA \(cur) je aktuální.", .informational)
            case .error(let msg):
                alert("Kontrola aktualizací selhala", msg, .warning)
            case .available(let rel):
                promptInstall(rel)
            }
        }
    }

    // Silent on launch: only speaks up when there's actually a newer release.
    static func checkOnLaunch() {
        Updater.checkLatest { result in
            if case .available(let rel) = result { promptInstall(rel) }
        }
    }

    private static func promptInstall(_ rel: Updater.Release) {
        let a = NSAlert()
        a.messageText = "K dispozici je HPA \(rel.version)"
        a.informativeText = rel.notes.isEmpty
            ? "Nainstalovat teď? HPA se po stažení sama restartuje."
            : String(rel.notes.prefix(500))
        a.alertStyle = .informational
        a.addButton(withTitle: "Aktualizovat")
        a.addButton(withTitle: "Otevřít stránku")
        a.addButton(withTitle: "Později")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            Updater.downloadAndInstall(rel) { msg in
                alert("Aktualizace selhala", msg, .warning)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(rel.htmlURL)
        default:
            break
        }
    }

    private static func alert(_ title: String, _ msg: String, _ style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = style
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
