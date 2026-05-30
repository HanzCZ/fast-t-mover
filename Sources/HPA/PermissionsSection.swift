import SwiftUI
import AppKit
import CoreLocation
import UserNotifications

// MARK: - Permission status model

enum PermStatus {
    case granted, denied, notDetermined, unknown

    var label: String {
        switch self {
        case .granted:       return "Granted"
        case .denied:        return "Denied"
        case .notDetermined: return "Not asked"
        case .unknown:       return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .granted:       return .green
        case .denied:        return .red
        case .notDetermined: return .orange
        case .unknown:       return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .granted:       return "checkmark.circle.fill"
        case .denied:        return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .unknown:       return "circle"
        }
    }
}

// MARK: - Reusable row

struct PermissionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let howTo: String
    let status: PermStatus
    let primaryAction: (label: String, perform: () -> Void)?
    let systemSettingsURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(title).font(.headline)
                    Spacer()
                    statusPill
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let action = primaryAction {
                        Button(action.label, action: action.perform)
                            .controlSize(.small)
                    }
                    if let url = systemSettingsURL {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }
                }
                if status == .denied {
                    Text(howTo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).font(.system(size: 9, weight: .bold))
            Text(status.label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Container

struct PermissionsSection: View {
    @State private var notifStatus: PermStatus = .unknown
    @State private var locationStatus: PermStatus = .unknown
    @State private var loginItemStatus: PermStatus = .unknown

    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PermissionRow(
                icon: "bell.fill",
                tint: .red,
                title: "Notifications",
                subtitle: "Banner with success / failure / info icon after every run.",
                howTo: "System Settings → Notifications → HPA → Allow Notifications + Banner style.",
                status: notifStatus,
                primaryAction: notifStatus == .notDetermined
                    ? ("Request", requestNotifications)
                    : nil,
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            )

            Divider()

            PermissionRow(
                icon: "location.fill",
                tint: .blue,
                title: "Location Services",
                subtitle: "Read your current Wi-Fi name to gate the run on allowed SSIDs (required on macOS 14.4+).",
                howTo: "System Settings → Privacy & Security → Location Services → HPA → On.",
                status: locationStatus,
                primaryAction: locationStatus == .notDetermined
                    ? ("Request", requestLocation)
                    : nil,
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
            )

            Divider()

            PermissionRow(
                icon: "power",
                tint: .green,
                title: "Launch at Login",
                subtitle: "Start HPA automatically when you log in.",
                howTo: "System Settings → General → Login Items & Extensions → HPA.",
                status: loginItemStatus,
                primaryAction: loginItemStatus == .granted
                    ? ("Disable", toggleLoginItem)
                    : ("Enable",  toggleLoginItem),
                systemSettingsURL: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            )
        }
        .onAppear(perform: refreshAll)
        .onReceive(refreshTimer) { _ in refreshAll() }
    }

    // MARK: - Actions

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in
            DispatchQueue.main.async { refreshNotifications() }
        }
    }

    private func requestLocation() {
        LocationPermissionManager.shared.ensureAuthorized { _ in
            refreshLocation()
        }
    }

    private func toggleLoginItem() {
        let next = loginItemStatus != .granted
        _ = LoginItem.setEnabled(next)
        refreshLoginItem()
    }

    // MARK: - Status refresh

    private func refreshAll() {
        refreshNotifications()
        refreshLocation()
        refreshLoginItem()
    }

    private func refreshNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .granted
            case .denied:                               status = .denied
            case .notDetermined:                        status = .notDetermined
            @unknown default:                           status = .unknown
            }
            DispatchQueue.main.async { notifStatus = status }
        }
    }

    private func refreshLocation() {
        let s = LocationPermissionManager.shared.status
        let mapped: PermStatus
        switch s {
        case .authorizedAlways, .authorized: mapped = .granted
        case .denied, .restricted:           mapped = .denied
        case .notDetermined:                 mapped = .notDetermined
        @unknown default:                    mapped = .unknown
        }
        locationStatus = mapped
    }

    private func refreshLoginItem() {
        loginItemStatus = LoginItem.isEnabled ? .granted : .notDetermined
    }
}
