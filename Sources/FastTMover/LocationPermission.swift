import Foundation
import CoreLocation

/// macOS 14.4+ gates Wi-Fi SSID behind Location Services. This wraps
/// CLLocationManager so the Settings UI can request the prompt at the
/// right moment (user clicks "Add current") and react to the outcome.
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionManager()

    private let manager = CLLocationManager()
    private var pendingCompletion: ((CLAuthorizationStatus) -> Void)?

    override private init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Request Location authorization if not yet decided; otherwise just
    /// report current status. Completion runs on the main queue.
    func ensureAuthorized(completion: @escaping (CLAuthorizationStatus) -> Void) {
        let current = manager.authorizationStatus
        if current != .notDetermined {
            DispatchQueue.main.async { completion(current) }
            return
        }
        pendingCompletion = completion
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let cb = pendingCompletion else { return }
        pendingCompletion = nil
        DispatchQueue.main.async { cb(manager.authorizationStatus) }
    }
}
