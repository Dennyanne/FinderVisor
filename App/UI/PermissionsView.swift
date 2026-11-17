// PermissionsView — onboarding / recovery for TCC permissions (plan Step 5, AC-S5).
//
// Public API:
//   struct PermissionsView: View { init(permissions: PermissionsService) }
// Polls every 1 s while visible. Starting the event tap on grant is the caller's job via
// `PermissionsService.onAccessibilityGranted`.

import SwiftUI

struct PermissionsView: View {
    let permissions: PermissionsService

    init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FinderVisor needs these permissions")
                .font(.headline)

            if permissions.staleGrantSuspected {
                staleGrantNotice
            }

            row(
                title: "Accessibility",
                detail: "Required to move and show/hide the Visor window and to detect the hotkeys.",
                granted: permissions.accessibilityGranted,
                status: permissions.accessibilityGranted ? "Granted" : "Not granted"
            ) {
                Button("Grant…") { permissions.requestAccessibility() }
            }

            row(
                title: "Automation → Finder",
                detail: "Required to create the dedicated Finder window.",
                granted: permissions.automation == .granted,
                status: automationStatus
            ) {
                HStack {
                    if permissions.automation == .notDetermined || permissions.automation == .finderNotRunning {
                        Button("Request") { Task { await permissions.requestAutomation() } }
                    }
                    Button("Open Settings…") { permissions.openSettings(.automation) }
                }
            }

            row(
                title: "Input Monitoring (info)",
                detail: "Usually not needed. If hotkeys do nothing while Accessibility is granted, enable it here.",
                granted: permissions.inputMonitoringGranted,
                status: permissions.inputMonitoringGranted ? "Granted" : "Not granted",
                isInfoOnly: true
            ) {
                Button("Open Settings…") { permissions.openSettings(.inputMonitoring) }
            }

            if permissions.allRequiredGranted {
                Label("All set. Hotkeys are active; you can close this window.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    private var automationStatus: String {
        switch permissions.automation {
        case .granted: "Granted"
        case .denied: "Denied — enable FinderVisor under Finder"
        case .notDetermined: "Not requested yet"
        case .finderNotRunning: "Finder is not running"
        case let .unknown(code): "Unknown (error \(code))"
        }
    }

    private var staleGrantNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Accessibility was granted before but is no longer recognised", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("""
                This usually happens after rebuilding FinderVisor with ad-hoc signing: System Settings still shows \
                the old entry, but it no longer matches this build. Quit FinderVisor, run `make reset-permissions` \
                in the project folder, relaunch, and grant again. A stable signing identity (see README) prevents this.
                """)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(
        title: String,
        detail: String,
        granted: Bool,
        status: String,
        isInfoOnly: Bool = false,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : (isInfoOnly ? "info.circle" : "xmark.circle.fill"))
                .foregroundStyle(granted ? .green : (isInfoOnly ? .secondary : .red))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status).font(.caption)
            }
            Spacer(minLength: 8)
            if !granted {
                actions()
            }
        }
    }
}
