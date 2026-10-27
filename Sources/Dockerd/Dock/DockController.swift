import AppKit
import DockerdCore
import os

final class DockController: NSObject {
    private let settingsStore: SettingsStore
    private let tracker: WindowTracker
    private let actions: WindowActions
    private var panels: [UInt32: DockPanelController] = [:]
    private var displays: [DisplayInfo] = []
    private let hoverCard = HoverCard()
    private let windowList = WindowListPanel()
    private var screenToken: NSObjectProtocol?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var screenWork: DispatchWorkItem?
    private var keyboardPanel: DockPanelController?
    private var keyboardReturnApp: NSRunningApplication?
    private var menuOpen = false
    private var sessionOrder: [String] = []
    private var sessionWindowOrder: [WindowID] = []
    private var badges: [DockBadge] = []
    private var launches = LaunchTracker()
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "dock")

    var onOpenSettings: (() -> Void)?
    var onShowPermissions: (() -> Void)?
    var accessibilityGranted = true {
        didSet { if oldValue != accessibilityGranted { rebuild() } }
    }

    init(settingsStore: SettingsStore, tracker: WindowTracker, actions: WindowActions) {
        self.settingsStore = settingsStore
        self.tracker = tracker
        self.actions = actions
        super.init()
        windowList.listDelegate = self
    }

    private var settings: Settings { settingsStore.settings }

    func start() {
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScreenRefresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            })
        }
        settingsStore.observe { [weak self] _, _ in
            self?.syncPanels()
            self?.rebuild()
        }
        syncPanels()
        rebuild()
    }

    func shutdown() {
        hoverCard.dismiss()
        windowList.dismiss()
        panels.values.forEach { $0.close() }
        panels.removeAll()
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
    }

    func setDockVisible(_ visible: Bool) {
        settingsStore.update { $0.dockVisible = visible }
    }

    private func scheduleScreenRefresh() {
        screenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.syncPanels()
                self?.rebuild()
            }
        }
        screenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    static func currentDisplays() -> [DisplayInfo] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            var uuid = "display-\(id)"
            if let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let string = CFUUIDCreateString(nil, cfUUID) as String? {
                uuid = string
            }
            return DisplayInfo(
                id: id,
                uuid: uuid,
                name: screen.localizedName,
                frame: DisplayGeometry.topLeftRect(fromCocoa: screen.frame, primaryHeight: primaryHeight),
                isPrimary: screen == primary)
        }
    }

    private func syncPanels() {
        let all = Self.currentDisplays()
        let docked = DockDisplaySelector.dockDisplays(all: all, settings: settings.displays)
        displays = docked
        let wanted = Dictionary(docked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, controller) in panels where wanted[id] == nil || wanted[id] != controller.display {
            controller.close()
            panels[id] = nil
        }
        for display in docked where panels[display.id] == nil {
            let controller = DockPanelController(display: display, delegate: self)
            controller.isInteractionLocked = { [weak self] in
                guard let self else { return false }
                return self.menuOpen || self.windowList.isVisible || self.keyboardPanel != nil
            }
            controller.panel.onResignKey = { [weak self, weak controller] in
                guard let self, let controller, self.keyboardPanel === controller else { return }
                self.endKeyboardNavigation(restoreFocus: false)
            }
            panels[display.id] = controller
        }
        hoverCard.dismiss()
        windowList.dismiss()
    }

    private func layoutInput(displayID: UInt32?) -> TaskbarInput {
        let current = settings
        return TaskbarInput(
            apps: tracker.appList,
            windows: tracker.windows,
            pins: current.pinned,
            policy: current.grouping,
            dockDisplays: displays,
            targetDisplayID: displayID,
            placement: current.displays.placement,
            currentSpaceOnly: current.displays.currentSpaceOnly,
            accessibilityGranted: accessibilityGranted,
            preferredOrder: sessionOrder,
            preferredWindowOrder: sessionWindowOrder,
            separatorAfterPinned: current.appearance.separatorAfterPinned,
            showDownloads: current.appearance.showDownloads,
            showTrash: current.appearance.showTrash)
    }

    func setBadges(_ next: [DockBadge]) {
        badges = next
        rebuild()
    }

    private static var normalizedPaths: [String: String] = [:]

    private static func normalizedPath(_ path: String) -> String {
        if let cached = normalizedPaths[path] { return cached }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        if normalizedPaths.count > 512 { normalizedPaths.removeAll() }
        normalizedPaths[path] = resolved
        return resolved
    }

    private func launch(path: String) {
        launches.begin(Self.normalizedPath(path), at: Date())
        actions.launch(path: path)
        rebuild()
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchTracker.timeout + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func fullScreenDisplayIDs() -> Set<UInt32> {
        guard accessibilityGranted else { return [] }
        var result = Set<UInt32>()
        var decided = Set<UInt32>()
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            if let window = appElement.element(kAXFocusedWindowAttribute),
               let display = WindowDisplayAssigner.display(for: window.frame, among: displays) {
                decided.insert(display.id)
                if window.bool("AXFullScreen") == true { result.insert(display.id) }
            }
        }
        for candidate in FullScreenCandidates.find(windows: tracker.windows, displays: displays)
        where !decided.contains(candidate.display) && !result.contains(candidate.display) {
            guard let element = tracker.element(for: candidate.window) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.25)
            if element.bool("AXFullScreen") == true { result.insert(candidate.display) }
        }
        return result
    }

    func rebuild() {
        let current = settings
        let running = Set(tracker.appList.compactMap { $0.bundlePath.map(Self.normalizedPath) })
        launches.settle(runningPaths: running, now: Date())
        let fullScreen = fullScreenDisplayIDs()
        for controller in panels.values {
            let items = DockDecorations.apply(
                to: TaskbarLayoutBuilder.build(layoutInput(displayID: controller.display.id)),
                badges: badges,
                launching: launches.paths,
                normalize: Self.normalizedPath)
            controller.update(
                items: items, appearance: current.appearance, visible: current.dockVisible,
                fullScreen: fullScreen.contains(controller.display.id))
            if let listID = windowList.itemID, windowList.isVisible,
               let item = items.first(where: { $0.id == listID }),
               controller.bar.itemViews.contains(where: { $0.item.id == listID }) {
                if item.windows.count > 1 { windowList.reload(item: item) } else { windowList.dismiss() }
            }
        }
        if let listID = windowList.itemID, !panels.values.contains(where: { $0.bar.itemViews.contains { $0.item.id == listID } }) {
            windowList.dismiss()
        }
    }

    private func controller(for view: NSView) -> DockPanelController? {
        panels.values.first { $0.panel === view.window }
    }

    private func screenRect(of view: NSView) -> NSRect {
        guard let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    func beginKeyboardNavigation() {
        let mouse = NSEvent.mouseLocation
        let target = panels.values.first { $0.screen?.frame.contains(mouse) == true } ?? panels.values.first
        guard let target else { return }
        keyboardReturnApp = NSWorkspace.shared.frontmostApplication
        keyboardPanel = target
        target.reveal()
        target.panel.allowsKey = true
        AppActivation.bringSelfForward()
        target.panel.makeKeyAndOrderFront(nil)
        target.bar.beginKeyboardFocus()
    }

    func endKeyboardNavigation(restoreFocus: Bool) {
        guard let panel = keyboardPanel else { return }
        keyboardPanel = nil
        panel.bar.endKeyboardFocus()
        panel.panel.allowsKey = false
        if panel.panel.isKeyWindow { panel.panel.resignKey() }
        if restoreFocus, let app = keyboardReturnApp, !app.isTerminated {
            actions.activateApp(pid: app.processIdentifier)
        }
        keyboardReturnApp = nil
    }

    private func perform(_ item: DockItem, from view: DockItemView) {
        hoverCard.dismiss()
        let wasNavigating = keyboardPanel != nil
        switch item.kind {
        case .accessibilityNotice:
            onShowPermissions?()
        case .separator:
            break
        case .downloads:
            let menu = SystemFolders.downloadsMenu()
            menu.delegate = self
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: 0), in: view)
        case .trash:
            SystemFolders.openTrash()
        case .launcher:
            if let path = item.bundlePath, !item.isLaunching { launch(path: path) }
        case .window:
            guard let window = item.window else { return }
            if settings.appearance.clickActiveWindowToMinimize && item.isFocusedWindow && window.presence == .onScreen && !wasNavigating {
                actions.minimize(window)
            } else {
                actions.activate(window)
            }
        case .application:
            if item.windows.count > 1 {
                if windowList.isVisible && windowList.itemID == item.id {
                    windowList.dismiss()
                } else if !windowList.wasJustDismissed(itemID: item.id) {
                    let edge = settings.appearance.edge
                    windowList.present(item: item, anchor: screenRect(of: view), edge: edge)
                }
                return
            }
            if let window = item.windows.first {
                if settings.appearance.clickActiveWindowToMinimize && item.isActive && window.isFocused && window.presence == .onScreen && !wasNavigating {
                    actions.minimize(window)
                } else {
                    actions.activate(window)
                }
            } else if item.isHidden, let pid = item.pids.first {
                actions.activateApp(pid: pid)
            } else {
                actions.reopen(item: item)
            }
        }
        if wasNavigating { endKeyboardNavigation(restoreFocus: false) }
    }

    private func pinnedApp(for item: DockItem) -> PinnedApp? {
        guard let path = item.bundlePath else { return nil }
        return PinnedApp(bundleID: item.bundleID, path: path, name: item.appName)
    }

    private func pinIndex(forItemIndex index: Int, in items: [DockItem], excluding key: String) -> Int {
        var keys: [String] = []
        for item in items.prefix(index) where item.isPinned && item.appKey != key && !keys.contains(item.appKey) {
            keys.append(item.appKey)
        }
        return keys.count
    }

    func menu(for item: DockItem) -> NSMenu {
        let menu = NSMenu(title: item.appName)
        menu.autoenablesItems = false
        menu.delegate = self

        if item.kind == .accessibilityNotice {
            menu.addItem(ClosureMenuItem("Grant Accessibility Access…") { [weak self] in self?.onShowPermissions?() })
            return menu
        }

        if item.kind == .downloads {
            menu.addItem(ClosureMenuItem("Open Downloads Folder") { NSWorkspace.shared.open(SystemFolders.downloads) })
            menu.addItem(ClosureMenuItem("Hide Downloads") { [weak self] in
                self?.settingsStore.update { $0.appearance.showDownloads = false }
            })
            return menu
        }

        if item.kind == .trash {
            menu.addItem(ClosureMenuItem("Open") { SystemFolders.openTrash() })
            menu.addItem(ClosureMenuItem("Empty Trash…") { SystemFolders.confirmEmptyTrash() })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Hide Trash") { [weak self] in
                self?.settingsStore.update { $0.appearance.showTrash = false }
            })
            return menu
        }

        if item.kind == .separator && !item.isPinned && item.id == TaskbarLayoutBuilder.systemSeparatorID {
            return menu
        }

        if item.kind == .separator {
            if item.isPinned {
                menu.addItem(ClosureMenuItem("Remove Separator") { [weak self] in
                    self?.settingsStore.update { $0.unpin(key: item.appKey) }
                })
            } else {
                menu.addItem(ClosureMenuItem("Hide Separator After Pinned Apps") { [weak self] in
                    self?.settingsStore.update { $0.appearance.separatorAfterPinned = false }
                })
            }
            return menu
        }

        if let window = item.window {
            appendWindowSection(menu, window: window, includeTitle: true)
            menu.addItem(.separator())
        } else if !item.windows.isEmpty {
            let header = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for window in item.windows {
                let state = DockItemDescriber.state(of: window).map { " — \($0)" } ?? ""
                let entry = ClosureMenuItem(window.displayTitle + state, state: window.isFocused && item.isActive ? .on : .off) { [weak self] in
                    self?.actions.activate(window)
                }
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

        if item.isRunning {
            if item.kind == .launcher || item.windows.isEmpty || item.kind == .window {
                menu.addItem(ClosureMenuItem("Show \(item.appName)") { [weak self] in
                    guard let self, let pid = item.pids.first else { return }
                    self.actions.activateApp(pid: pid)
                })
            }
            if let path = item.bundlePath {
                menu.addItem(ClosureMenuItem("New Window or Reopen") { [weak self] in self?.actions.launch(path: path) })
            }
            menu.addItem(ClosureMenuItem("Hide \(item.appName)") { [weak self] in self?.actions.hide(pids: item.pids) })
        } else if let path = item.bundlePath {
            menu.addItem(ClosureMenuItem("Open \(item.appName)") { [weak self] in self?.launch(path: path) })
        }

        if let path = item.bundlePath {
            menu.addItem(ClosureMenuItem("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }

        menu.addItem(.separator())
        if item.isPinned {
            menu.addItem(ClosureMenuItem("Add Separator After") { [weak self] in
                self?.settingsStore.update { settings in
                    guard let index = settings.pinned.firstIndex(where: { pinKeyMatches($0, item: item) }) else { return }
                    settings.pin(.separator(), at: index + 1)
                }
            })
            menu.addItem(ClosureMenuItem("Unpin from Dockerd") { [weak self] in
                self?.settingsStore.update { settings in
                    settings.pinned.removeAll { pinKeyMatches($0, item: item) }
                }
            })
        } else if let pinned = pinnedApp(for: item) {
            menu.addItem(ClosureMenuItem("Pin to Dockerd") { [weak self] in
                self?.settingsStore.update { $0.pin(pinned) }
            })
        }

        if let bundleID = item.bundleID {
            let groupingItem = NSMenuItem(title: "Window Grouping", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "Window Grouping")
            submenu.autoenablesItems = false
            let policy = settings.grouping
            let explicit = policy.explicitMode(for: bundleID)
            let defaultLabel = "Use Default (\(policy.defaultMode == .grouped ? "Group" : "Separate"))"
            submenu.addItem(ClosureMenuItem(defaultLabel, state: explicit == nil ? .on : .off) { [weak self] in
                self?.settingsStore.update { $0.grouping.setMode(nil, for: bundleID) }
            })
            submenu.addItem(ClosureMenuItem("Group Windows", state: explicit == .grouped ? .on : .off) { [weak self] in
                self?.settingsStore.update { $0.grouping.setMode(.grouped, for: bundleID) }
            })
            submenu.addItem(ClosureMenuItem("Show Each Window Separately", state: explicit == .ungrouped ? .on : .off) { [weak self] in
                self?.settingsStore.update { $0.grouping.setMode(.ungrouped, for: bundleID) }
            })
            groupingItem.submenu = submenu
            menu.addItem(groupingItem)
        }

        if item.kind == .window && settings.appearance.edge.isHorizontal {
            let showing = settings.appearance.showWindowTitles
            menu.addItem(ClosureMenuItem("Show Window Titles", state: showing ? .on : .off) { [weak self] in
                self?.settingsStore.update { $0.appearance.showWindowTitles = !showing }
            })
        }

        menu.addItem(.separator())
        if item.isRunning {
            menu.addItem(ClosureMenuItem("Quit \(item.appName)") { [weak self] in self?.actions.quit(pids: item.pids) })
        }
        menu.addItem(ClosureMenuItem("Dockerd Settings…") { [weak self] in self?.onOpenSettings?() })
        return menu
    }

    private func appendWindowSection(_ menu: NSMenu, window: WindowInfo, includeTitle: Bool) {
        if includeTitle {
            let title = NSMenuItem(title: window.displayTitle, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }
        menu.addItem(ClosureMenuItem("Bring to Front") { [weak self] in self?.actions.activate(window) })
        if window.isMinimized {
            menu.addItem(ClosureMenuItem("Restore") { [weak self] in self?.actions.restore(window) })
        } else {
            menu.addItem(ClosureMenuItem("Minimize") { [weak self] in self?.actions.minimize(window) })
        }
        menu.addItem(ClosureMenuItem("Close Window") { [weak self] in self?.actions.close(window) })
    }
}

extension DockController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        hoverCard.dismiss()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }
}

extension DockController: DockBarViewDelegate {
    func dockItemClicked(_ view: DockItemView) {
        perform(view.item, from: view)
    }

    func dockItemMenu(_ view: DockItemView) -> NSMenu? {
        hoverCard.dismiss()
        windowList.dismiss()
        let menu = menu(for: view.item)
        return menu.items.isEmpty ? nil : menu
    }

    func dockItemHoverChanged(_ view: DockItemView, hovering: Bool) {
        guard settings.appearance.showHoverPreviews, view.item.kind != .separator else { return }
        if hovering && !menuOpen && !(windowList.isVisible && windowList.itemID == view.item.id) {
            hoverCard.schedule(item: view.item, anchor: screenRect(of: view), edge: settings.appearance.edge)
        } else {
            hoverCard.dismiss()
        }
    }

    func dockItemCanDrag(_ view: DockItemView) -> Bool {
        switch view.item.kind {
        case .separator: return view.item.isPinned
        case .accessibilityNotice, .downloads, .trash: return false
        default: return view.item.bundlePath != nil || view.item.isRunning
        }
    }

    private func isMovable(_ item: DockItem) -> Bool {
        !TaskbarLayoutBuilder.isFixed(item)
    }

    private func reordered(moving key: String, toIndex index: Int, in items: [DockItem]) -> [String] {
        let following = items.dropFirst(min(index, items.count)).first { $0.appKey != key && isMovable($0) }
        let preceding = items.prefix(min(index, items.count)).last { $0.appKey != key && isMovable($0) }
        let order = TaskbarLayoutBuilder.keyOrder(layoutInput(displayID: nil))
        let base = order.contains(key) ? order : order + [key]
        return TaskbarOrder.move(key, in: base, before: following?.appKey, orAfter: preceding?.appKey)
    }

    private func moveWindow(_ id: WindowID, appKey: String, toIndex index: Int, in items: [DockItem]) -> Bool {
        let split = min(index, items.count)
        let isSibling = { (item: DockItem?) in item?.kind == .window && item?.appKey == appKey }
        let following = items[split...].first { $0.windows.first?.id != id }
        let preceding = items[..<split].last { $0.windows.first?.id != id }
        guard isSibling(following) || isSibling(preceding) else { return false }
        sessionWindowOrder = TaskbarOrder.move(
            id,
            in: TaskbarLayoutBuilder.windowOrder(layoutInput(displayID: nil)),
            before: isSibling(following) ? following?.windows.first?.id : nil,
            orAfter: isSibling(preceding) ? preceding?.windows.first?.id : nil)
        rebuild()
        return true
    }

    func dockBar(_ bar: DockBarView, moveItemWithKey key: String, windowID: WindowID?, toIndex index: Int) {
        let items = bar.itemViews.map(\.item)
        if let windowID, moveWindow(windowID, appKey: key, toIndex: index, in: items) { return }
        guard let source = items.first(where: { $0.appKey == key }), isMovable(source) else { return }
        let order = reordered(moving: key, toIndex: index, in: items)
        sessionOrder = order
        if source.isPinned {
            settingsStore.update { $0.reorderPins(by: order) }
        }
        rebuild()
    }

    func dockBar(_ bar: DockBarView, dropApplicationAt url: URL, toIndex index: Int) {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let pin = PinnedApp(bundleID: bundle?.bundleIdentifier, path: url.path, name: name)
        let items = bar.itemViews.map(\.item)
        let target = pinIndex(forItemIndex: index, in: items, excluding: pin.key)
        let order = reordered(moving: pin.key, toIndex: index, in: items)
        sessionOrder = order
        settingsStore.update { settings in
            settings.pin(pin, at: target)
            settings.reorderPins(by: order)
        }
        rebuild()
    }

    func dockBarKeyboardExit(_ bar: DockBarView) {
        endKeyboardNavigation(restoreFocus: true)
    }
}

private func pinKeyMatches(_ pin: PinnedApp, item: DockItem) -> Bool {
    if let bundleID = pin.bundleID, let other = item.bundleID {
        return bundleID.caseInsensitiveCompare(other) == .orderedSame
    }
    return pin.path == item.bundlePath || pin.key == item.appKey
}

extension DockController: WindowListPanelDelegate {
    func windowList(_ panel: WindowListPanel, activate window: WindowInfo) {
        panel.dismiss()
        actions.activate(window)
    }

    func windowList(_ panel: WindowListPanel, menuFor window: WindowInfo) -> NSMenu? {
        let menu = NSMenu(title: window.displayTitle)
        menu.autoenablesItems = false
        menu.delegate = self
        appendWindowSection(menu, window: window, includeTitle: false)
        return menu
    }

    func windowList(_ panel: WindowListPanel, close window: WindowInfo) {
        actions.close(window)
    }
}
