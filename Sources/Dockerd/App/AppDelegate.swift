import AppKit
import DockerdCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "app")
    private var settingsStore: SettingsStore!
    private let permissions = PermissionController()
    private let tracker = WindowTracker()
    private let badgeReader = DockBadgeReader()
    private var actions: WindowActions!
    private var dock: DockController!
    private var systemDock: SystemDockController!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let url: URL
        do {
            url = try SettingsStore.defaultFileURL()
        } catch {
            logger.error("Application Support unavailable: \(error.localizedDescription, privacy: .public)")
            url = FileManager.default.temporaryDirectory.appendingPathComponent("Dockerd/settings.json")
        }
        settingsStore = SettingsStore(fileURL: url)
        actions = WindowActions(tracker: tracker)
        dock = DockController(settingsStore: settingsStore, tracker: tracker, actions: actions)
        dock.onOpenSettings = { [weak self] in self?.openSettings() }
        dock.onShowPermissions = { [weak self] in self?.showPermissionHelp() }
        statusItem = StatusItemController(settingsStore: settingsStore, permissions: permissions)
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onShowPermissions = { [weak self] in self?.showPermissionHelp() }
        statusItem.onKeyboardNavigation = { [weak self] in self?.dock.beginKeyboardNavigation() }
        statusItem.onSystemDockHelp = { [weak self] in self?.openSettings(tab: "Access") }

        tracker.onChange = { [weak self] in self?.dock.rebuild() }
        tracker.onAccessibilityLost = { [weak self] in self?.permissions.reportAPIDisabled() }
        permissions.observe { [weak self] state in self?.permissionChanged(state) }

        permissions.start()
        tracker.start(accessibility: permissions.state.isGranted)
        dock.accessibilityGranted = permissions.state.isGranted
        dock.start()
        systemDock = SystemDockController(store: settingsStore)
        systemDock.start()
        LoginItem.enableOnFirstLaunch(store: settingsStore)
        badgeReader.onChange = { [weak self] badges in self?.dock.setBadges(badges) }
        badgeReader.setEnabled(permissions.state.isGranted)
        statusItem.refresh()
        if !permissions.state.isGranted { showPermissionHelp() }
        logger.info("Dockerd started; accessibility \(self.permissions.state.rawValue, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemDock?.restoreBeforeQuit()
        settingsStore?.flush()
        tracker.stop()
        badgeReader.setEnabled(false)
        dock?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func permissionChanged(_ state: AccessibilityPermission) {
        tracker.setAccessibility(enabled: state.isGranted)
        dock.accessibilityGranted = state.isGranted
        badgeReader.setEnabled(state.isGranted)
        statusItem.refresh()
        switch state {
        case .granted:
            onboarding?.close()
        case .revoked:
            showPermissionHelp()
        case .denied, .unknown:
            break
        }
    }

    private func showPermissionHelp() {
        if permissions.state.isGranted {
            openSettings(tab: "Access")
            return
        }
        let controller = onboarding ?? OnboardingWindowController(permissions: permissions)
        onboarding = controller
        controller.present(for: permissions.state)
    }

    private func openSettings(tab: String? = nil) {
        let controller = settingsWindow ?? SettingsWindowController(
            settingsStore: settingsStore, permissions: permissions, tracker: tracker)
        settingsWindow = controller
        controller.present(tab: tab)
    }
}
