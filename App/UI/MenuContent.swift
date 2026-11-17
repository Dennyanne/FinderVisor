import SwiftUI

/// Menu bar menu: Toggle Visor, Settings…, Launch at Login (checkmark), Quit.
struct MenuContent: View {
    let environment: AppEnvironment

    var body: some View {
        Button("Toggle Visor") { environment.toggleVisor() }
        Divider()
        Button("Settings…") { environment.showSettings() }
            .keyboardShortcut(",")
        Toggle("Launch at Login", isOn: Binding(
            get: { environment.loginItem.isEnabled },
            set: { environment.loginItem.setEnabled($0) }
        ))
        Divider()
        Button("Quit FinderVisor") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
