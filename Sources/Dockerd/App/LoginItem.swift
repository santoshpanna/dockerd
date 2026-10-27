import AppKit
import DockerdCore
import os
import ServiceManagement

enum LoginItem {
    private static let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "login-item")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            logger.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func enableOnFirstLaunch(store: SettingsStore) {
        guard !store.settings.loginItemConfigured else { return }
        if setEnabled(true) {
            store.update { $0.loginItemConfigured = true }
        }
    }
}
