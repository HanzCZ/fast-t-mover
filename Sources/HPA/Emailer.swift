import Foundation
import AppKit

// Always opens a draft in Apple Mail specifically (not the system default mail
// client) via AppleScript, with the files attached. Targeting `application
// "Mail"` hard-pins Apple Mail regardless of the default mailto handler.
//
// Note: scripting Mail needs Automation permission — macOS prompts once
// (System Settings → Privacy & Security → Automation → HPA → Mail).
enum Emailer {
    @discardableResult
    static func composeDraft(to: String, subject: String, body: String, attachments: [URL]) -> Bool {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        // Trailing blank line so the attachment lands cleanly below the body.
        let bodyExpr = (body + "\n").components(separatedBy: "\n")
            .map { "\"\(esc($0))\"" }
            .joined(separator: " & linefeed & ")
        let attachLines = attachments.map {
            "        make new attachment with properties {file name:(POSIX file \"\(esc($0.path))\")} at after the last paragraph"
        }.joined(separator: "\n")

        let script = """
        set theBody to \(bodyExpr)
        tell application "Mail"
            set msg to make new outgoing message with properties {subject:"\(esc(subject))", content:theBody, visible:true}
            tell msg
                make new to recipient with properties {address:"\(esc(to))"}
            end tell
            delay 0.3
            tell content of msg
        \(attachLines)
            end tell
            activate
        end tell
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hpa_mail_\(UUID().uuidString).applescript")
        do { try script.write(to: tmp, atomically: true, encoding: .utf8) }
        catch { return false }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = [tmp.path]
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
