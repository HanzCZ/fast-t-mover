import Foundation
import AppKit

// Open a draft in the default mail client (Apple Mail) with recipient,
// subject, body and a real file attachment. Primary path is the native
// "share via email" service (clean attachment, no Automation permission);
// AppleScript is a fallback.
enum Emailer {
    @discardableResult
    static func composeDraft(to: String, subject: String, body: String, attachment: URL) -> Bool {
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = [to]
            service.subject = subject
            let items: [Any] = [body, attachment]   // body as text, file as attachment
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return true
            }
        }
        return composeViaAppleScript(to: to, subject: subject, body: body, attachment: attachment)
    }

    private static func composeViaAppleScript(to: String, subject: String,
                                              body: String, attachment: URL) -> Bool {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let bodyExpr = body.components(separatedBy: "\n")
            .map { "\"\(esc($0))\"" }
            .joined(separator: " & linefeed & ")
        let script = """
        set theBody to \(bodyExpr)
        tell application "Mail"
            set msg to make new outgoing message with properties {subject:"\(esc(subject))", content:theBody, visible:true}
            tell msg
                make new to recipient with properties {address:"\(esc(to))"}
            end tell
            delay 0.5
            tell content of msg
                make new attachment with properties {file name:(POSIX file "\(esc(attachment.path))")} at after the last paragraph
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
