import AppKit
import DockerdCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsStore: SettingsStore
    private let permissions: PermissionController
    var onOpenSettings: (() -> Void)?
    var onShowPermissions: (() -> Void)?
    var onKeyboardNavigation: (() -> Void)?
    var onSystemDockHelp: (() -> Void)?

    init(settingsStore: SettingsStore, permissions: PermissionController) {
        self.settingsStore = settingsStore
        self.permissions = permissions
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Dockerd")
                ?? NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Dockerd")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Dockerd"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func refresh() {
        statusItem.button?.appearsDisabled = !permissions.state.isGranted
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let visible = settingsStore.settings.dockVisible
        menu.addItem(ClosureMenuItem(visible ? "Hide Dock" : "Show Dock") { [weak self] in
            self?.settingsStore.update { $0.dockVisible.toggle() }
        })
        let navigate = ClosureMenuItem("Navigate Dock with Keyboard") { [weak self] in
            self?.onKeyboardNavigation?()
        }
        navigate.isEnabled = visible
        menu.addItem(navigate)
        menu.addItem(.separator())

        let state = permissions.state
        let permissionTitle = state.isGranted ? "Accessibility: Allowed" : "Accessibility: Not Allowed — Fix…"
        let permission = ClosureMenuItem(permissionTitle) { [weak self] in self?.onShowPermissions?() }
        permission.image = NSImage(
            systemSymbolName: state.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil)
        menu.addItem(permission)
        menu.addItem(ClosureMenuItem("Hiding the System Dock…") { [weak self] in self?.onSystemDockHelp?() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [weak self] in self?.onOpenSettings?() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit Dockerd", key: "q") { NSApp.terminate(nil) })
    }
}
