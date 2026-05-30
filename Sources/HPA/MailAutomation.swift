import Foundation
import Carbon
import AppKit

// Automation (Apple Events) permission for controlling Apple Mail — needed by
// the e-mail draft feature, which scripts Mail. Surfaced in Settings →
// Permissions so the user can see/grant it.
enum MailAutomation {
    static let mailBundleID = "com.apple.mail"

    static func status() -> PermStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: mailBundleID)
        guard let desc = target.aeDesc else { return .unknown }
        let err = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch err {
        case noErr:   return .granted
        case -1743:   return .denied         // errAEEventNotPermitted
        case -1744:   return .notDetermined  // errAEEventWouldRequireUserConsent
        case -600:    return .notDetermined  // procNotFound (Mail not running yet)
        default:      return .unknown
        }
    }

    // Trigger the consent prompt the same way the real feature does: a tiny
    // AppleScript against Mail. macOS shows the "HPA wants to control Mail"
    // dialog; granting it unlocks the e-mail drafts.
    static func request(_ completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.launchPath = "/usr/bin/osascript"
            p.arguments = ["-e", "tell application \"Mail\" to count accounts"]
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { completion() }
        }
    }
}
