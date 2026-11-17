// SettingsView — the Settings window content: exactly four controls (AC-S3).
//
// Public API:
//   struct SettingsView: View { init(settings: SettingsStore, loginItem: LoginItemService) }
// Intended for `Window("Settings", id: "settings") { SettingsView(settings:loginItem:) }`.

import SwiftUI
import VisorCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let loginItem: LoginItemService

    init(settings: SettingsStore, loginItem: LoginItemService) {
        self.settings = settings
        self.loginItem = loginItem
    }

    var body: some View {
        Form {
            Picker("Double-tap key:", selection: $settings.doubleTapModifier) {
                Text("Option").tag(ModifierKey?.some(.option))
                Text("Control").tag(ModifierKey?.some(.control))
                Text("Command").tag(ModifierKey?.some(.command))
                Text("Shift").tag(ModifierKey?.some(.shift))
                Divider()
                Text("Off").tag(ModifierKey?.none)
            }

            LabeledContent("Shortcut:") {
                KeyRecorderField(combo: $settings.combo) { recording in
                    settings.isRecordingCombo = recording
                }
            }

            LabeledContent("Visor height:") {
                HStack {
                    Slider(
                        value: heightBinding,
                        in: Double(VisorSettings.heightPercentRange.lowerBound)...Double(VisorSettings.heightPercentRange.upperBound),
                        step: Double(VisorSettings.heightPercentStep)
                    )
                    .frame(width: 180)
                    Text("\(settings.heightPercent)%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at Login", isOn: loginBinding)
                if loginItem.requiresApproval {
                    Text("Approve FinderVisor in System Settings ▸ General ▸ Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { Double(settings.heightPercent) },
            set: { settings.heightPercent = Int($0.rounded()) }
        )
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }
}
