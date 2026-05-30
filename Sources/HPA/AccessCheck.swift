import Foundation

/// Pre-flight check that exercises every step the worker script would take:
/// source folder accessibility, SMB mount, destination folder, and a
/// write→size-verify→delete roundtrip. Each step is appended to the log,
/// so this also serves as a diagnostic trail.
enum AccessCheck {
    struct Result {
        let ok: Bool
        let lines: [String]
    }

    static func run(sourceDir: String, smbURL: String, destSubdir: String) -> Result {
        var lines: [String] = []
        var ok = true

        func add(_ s: String) {
            lines.append(s)
            appendToLog(s)
        }

        add("=== Verify Access ===")

        // 1. Source folder
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: sourceDir, isDirectory: &isDir),
           isDir.boolValue {
            add("✓ Source exists: \(sourceDir)")
            if FileManager.default.isReadableFile(atPath: sourceDir) {
                add("✓ Source readable")
            } else {
                add("✗ Source NOT readable")
                ok = false
            }
        } else {
            add("✗ Source missing: \(sourceDir)")
            ok = false
        }

        // 2. Mount SMB if needed
        let share = mountShareName(from: smbURL)
        let mountPoint = "/Volumes/\(share)"
        if isMounted(at: mountPoint) {
            add("✓ Already mounted at \(mountPoint)")
        } else {
            add("• Mounting \(smbURL) …")
            if mount(smbURL: smbURL, expected: mountPoint) {
                add("✓ Mounted at \(mountPoint)")
            } else {
                add("✗ Failed to mount \(smbURL). Check Keychain credentials & network.")
                return Result(ok: false, lines: lines)
            }
        }

        // 3. Destination subfolder
        let destDir = "\(mountPoint)/\(destSubdir)"
        if FileManager.default.fileExists(atPath: destDir) {
            add("✓ Destination exists: \(destDir)")
        } else {
            do {
                try FileManager.default.createDirectory(
                    atPath: destDir, withIntermediateDirectories: true)
                add("✓ Created destination: \(destDir)")
            } catch {
                add("✗ Cannot create destination: \(error.localizedDescription)")
                return Result(ok: false, lines: lines)
            }
        }

        // 4. Write → verify size → delete roundtrip
        let testName = ".fasttmover_verify_\(UUID().uuidString).bin"
        let testPath = "\(destDir)/\(testName)"
        let payload = Data(repeating: 0x42, count: 1024)
        do {
            try payload.write(to: URL(fileURLWithPath: testPath))
            let attrs = try FileManager.default.attributesOfItem(atPath: testPath)
            let written = (attrs[.size] as? NSNumber)?.intValue ?? -1
            if written == payload.count {
                add("✓ Write+size roundtrip OK (\(written) bytes)")
            } else {
                add("✗ SIZE MISMATCH: wrote \(payload.count) B, got \(written) B. DATA LOSS RISK — do NOT trust this mount!")
                ok = false
            }
            try? FileManager.default.removeItem(atPath: testPath)
        } catch {
            add("✗ Roundtrip failed: \(error.localizedDescription)")
            ok = false
            try? FileManager.default.removeItem(atPath: testPath)
        }

        add(ok ? "=== All checks passed ===" : "=== Some checks failed ===")
        return Result(ok: ok, lines: lines)
    }

    // MARK: - Helpers

    private static func mountShareName(from url: String) -> String {
        // smb://host/share[/...] → share
        let stripped = url.replacingOccurrences(of: "smb://", with: "")
        let parts = stripped.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count >= 2 ? String(parts[1]) : "share"
    }

    private static func isMounted(at path: String) -> Bool {
        let task = Process()
        task.launchPath = "/sbin/mount"
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        let out = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return out.contains(" on \(path) ")
    }

    private static func mount(smbURL: String, expected mountPoint: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "mount volume \"\(smbURL)\""]
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        // Wait up to 10 s for the mount point to appear.
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.5)
            if isMounted(at: mountPoint) { return true }
        }
        return false
    }

    private static func appendToLog(_ line: String) {
        let logFile = "\(NSHomeDirectory())/.local/state/fast_t_mover/torrent_mover.log"
        let stamp = isoFormatter.string(from: Date())
        let entry = "[\(stamp)] \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: logFile)
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
