import AppKit
import SwiftUI

@main
struct FinderVisorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("FinderVisor", systemImage: "rectangle.bottomhalf.inset.filled") {
            MenuContent(environment: appDelegate.environment)
                .onAppear { appDelegate.environment.loginItem.refresh() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
    }
}
