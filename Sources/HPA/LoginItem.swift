import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService.mainApp so the Settings UI can toggle
/// "Launch at login" without dealing with the framework directly.
enum LoginItem {
    /// True if the app is registered to launch at login (status == .enabled).
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, an error message string on failure.
    @discardableResult
    static func setEnabled(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "\(error)"
        }
    }
}
