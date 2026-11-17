// LoginItemService — Launch at Login via SMAppService.mainApp (AC-S4). The status is never stored; it is read back.
//
// Public API (main actor, @Observable):
//   init()
//   private(set) var status: SMAppService.Status
//   var isEnabled: Bool { get }            // status == .enabled (menu checkmark / settings toggle)
//   var requiresApproval: Bool { get }     // status == .requiresApproval
//   private(set) var lastError: String?    // last register/unregister failure, for display
//   func refresh()                         // re-read status (call when a menu/settings view appears)
//   func setEnabled(_ enabled: Bool)       // register/unregister; .requiresApproval → opens Login Items settings

import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemService {
    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init() {
        status = SMAppService.mainApp.status
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        let service = SMAppService.mainApp
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            refresh()
            return
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if enabled, status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
