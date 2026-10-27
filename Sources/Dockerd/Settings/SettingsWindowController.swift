import AppKit
import DockerdCore

final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    init(settingsStore: SettingsStore, permissions: PermissionController, tracker: WindowTracker) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Dockerd Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabs.tabStyle = .toolbar
        let panes: [(NSViewController, String, String)] = [
            (GeneralPane(store: settingsStore), "General", "gearshape"),
            (GroupingPane(store: settingsStore, tracker: tracker), "Grouping", "square.stack.3d.up"),
            (PinnedPane(store: settingsStore), "Pinned", "pin"),
            (DisplaysPane(store: settingsStore), "Displays", "display.2"),
            (PermissionsPane(permissions: permissions, store: settingsStore), "Access", "lock.shield"),
        ]
        for (controller, title, symbol) in panes {
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        window.setContentSize(NSSize(width: 620, height: 540))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(tab: String? = nil) {
        if let tab, let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = index
        }
        window?.center()
        AppActivation.bringSelfForward()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum Form {
    static func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { label, control in
            let text = NSTextField(labelWithString: label.isEmpty ? "" : label + ":")
            text.alignment = .right
            return [text, control]
        })
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    static func page(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 620),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
        return container
    }

    static func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 540
        return label
    }

    static func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    static func checkbox(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: target, action: action)
    }

    static func slider(_ range: ClosedRange<Double>, target: AnyObject, action: Selector) -> NSSlider {
        let slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: target, action: action)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return slider
    }

    static func appCell(icon: NSImage, title: String, subtitle: String?) -> NSView {
        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let name = NSTextField(labelWithString: title)
        name.lineBreakMode = .byTruncatingTail
        var views: [NSView] = [iconView, name]
        if let subtitle {
            let detail = NSTextField(labelWithString: subtitle)
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingMiddle
            views.append(detail)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    static func chooseApplication(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        AppActivation.bringSelfForward()
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    static func appDetails(url: URL) -> (bundleID: String?, name: String) {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (bundle?.bundleIdentifier, name)
    }
}

final class GeneralPane: NSViewController {
    private let store: SettingsStore
    private let edge = NSPopUpButton()
    private var iconSize: NSSlider!
    private var spacing: NSSlider!
    private var titleWidth: NSSlider!
    private var delay: NSSlider!
    private var titles: NSButton!
    private var autoHide: NSButton!
    private var clickMinimize: NSButton!
    private var previews: NSButton!
    private var visible: NSButton!
    private var pinnedSeparator: NSButton!
    private var downloads: NSButton!
    private var trash: NSButton!
    private var login: NSButton!
    private let loginNote = NSTextField(wrappingLabelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        edge.addItems(withTitles: ["Bottom", "Left", "Right"])
        edge.target = self
        edge.action = #selector(changed)
        iconSize = Form.slider(AppearanceSettings.iconSizeRange, target: self, action: #selector(changed))
        spacing = Form.slider(AppearanceSettings.spacingRange, target: self, action: #selector(changed))
        titleWidth = Form.slider(AppearanceSettings.titleWidthRange, target: self, action: #selector(changed))
        delay = Form.slider(AppearanceSettings.autoHideDelayRange, target: self, action: #selector(changed))
        visible = Form.checkbox("Show Dockerd's dock", target: self, action: #selector(changed))
        titles = Form.checkbox("Show titles next to separate windows (bottom edge only)", target: self, action: #selector(changed))
        autoHide = Form.checkbox("Automatically hide and show the dock", target: self, action: #selector(changed))
        clickMinimize = Form.checkbox("Clicking the focused window minimizes it", target: self, action: #selector(changed))
        previews = Form.checkbox("Show hover cards", target: self, action: #selector(changed))
        pinnedSeparator = Form.checkbox("Show a separator after pinned apps", target: self, action: #selector(changed))
        downloads = Form.checkbox("Show Downloads at the end", target: self, action: #selector(changed))
        trash = Form.checkbox("Show Trash at the end", target: self, action: #selector(changed))
        login = Form.checkbox("Open Dockerd at login", target: self, action: #selector(toggleLogin))
        loginNote.textColor = .secondaryLabelColor
        loginNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let restore = NSButton(title: "Restore Defaults…", target: self, action: #selector(restoreDefaults))

        let grid = Form.grid([
            ("", login),
            ("", loginNote),
            ("", visible),
            ("Position on screen", edge),
            ("Icon size", iconSize),
            ("Spacing", spacing),
            ("Window title width", titleWidth),
            ("", titles),
            ("", autoHide),
            ("Hide delay", delay),
            ("", clickMinimize),
            ("", previews),
            ("", pinnedSeparator),
            ("", downloads),
            ("", trash),
        ])
        view = Form.page([grid, restore])
        store.observe { [weak self] _, _ in self?.refresh() }
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLogin()
    }

    private func refreshLogin() {
        login.state = LoginItem.isEnabled || LoginItem.needsApproval ? .on : .off
        loginNote.stringValue = LoginItem.needsApproval
            ? "Allow Dockerd in System Settings › General › Login Items to finish turning this on."
            : ""
        loginNote.isHidden = !LoginItem.needsApproval
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(login.state == .on)
        store.update { $0.loginItemConfigured = true }
        refreshLogin()
    }

    private func refresh() {
        let a = store.settings.appearance
        visible.state = store.settings.dockVisible ? .on : .off
        edge.selectItem(at: DockEdge.allCases.firstIndex(of: a.edge) ?? 0)
        iconSize.doubleValue = a.iconSize
        spacing.doubleValue = a.spacing
        titleWidth.doubleValue = a.titleWidth
        delay.doubleValue = a.autoHideDelay
        delay.isEnabled = a.autoHide
        titles.state = a.showWindowTitles ? .on : .off
        autoHide.state = a.autoHide ? .on : .off
        clickMinimize.state = a.clickActiveWindowToMinimize ? .on : .off
        previews.state = a.showHoverPreviews ? .on : .off
        pinnedSeparator.state = a.separatorAfterPinned ? .on : .off
        downloads.state = a.showDownloads ? .on : .off
        trash.state = a.showTrash ? .on : .off
    }

    @objc private func changed() {
        store.update { s in
            s.dockVisible = visible.state == .on
            s.appearance.edge = DockEdge.allCases[max(edge.indexOfSelectedItem, 0)]
            s.appearance.iconSize = iconSize.doubleValue.rounded()
            s.appearance.spacing = spacing.doubleValue.rounded()
            s.appearance.titleWidth = titleWidth.doubleValue.rounded()
            s.appearance.autoHideDelay = (delay.doubleValue * 10).rounded() / 10
            s.appearance.showWindowTitles = titles.state == .on
            s.appearance.autoHide = autoHide.state == .on
            s.appearance.clickActiveWindowToMinimize = clickMinimize.state == .on
            s.appearance.showHoverPreviews = previews.state == .on
            s.appearance.separatorAfterPinned = pinnedSeparator.state == .on
            s.appearance.showDownloads = downloads.state == .on
            s.appearance.showTrash = trash.state == .on
        }
    }

    @objc private func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "Restore default settings?"
        alert.informativeText = "This resets appearance, grouping rules, pinned apps and display options, and shows the system Dock again if Dockerd hid it."
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { self?.store.restoreDefaults() }
            }
        }
    }
}

final class GroupingPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: SettingsStore
    private let tracker: WindowTracker
    private let table = NSTableView()
    private let defaultMode = NSPopUpButton()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private var rules: [GroupingRule] = []

    init(store: SettingsStore, tracker: WindowTracker) {
        self.store = store
        self.tracker = tracker
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        defaultMode.addItems(withTitles: ["Group windows into one entry", "Show each window separately"])
        defaultMode.target = self
        defaultMode.action = #selector(defaultChanged)

        let app = NSTableColumn(identifier: .init("app"))
        app.title = "Application"
        app.width = 330
        let mode = NSTableColumn(identifier: .init("mode"))
        mode.title = "Windows"
        mode.width = 190
        table.addTableColumn(app)
        table.addTableColumn(mode)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 556).isActive = true

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add application")
        addButton.bezelStyle = .smallSquare
        addButton.target = self
        addButton.action = #selector(addRule)
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove rule")
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removeRule)
        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.spacing = 0

        view = Form.page([
            Form.grid([("Apps without a rule", defaultMode)]),
            Form.header("Per-app rules"),
            scroll,
            buttons,
            Form.note("Rules match the exact bundle identifier, so variants such as VS Code, VS Code Insiders, VSCodium and Cursor are configured independently. Changes apply immediately. You can also right-click any app in the dock › Window Grouping."),
        ])
        store.observe { [weak self] _, _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let policy = store.settings.grouping
        defaultMode.selectItem(at: policy.defaultMode == .grouped ? 0 : 1)
        rules = policy.sortedRules
        table.reloadData()
    }

    @objc private func defaultChanged() {
        let mode: GroupingMode = defaultMode.indexOfSelectedItem == 1 ? .ungrouped : .grouped
        store.update { $0.grouping.defaultMode = mode }
    }

    @objc private func addRule() {
        let menu = NSMenu()
        let existing = Set(rules.map(\.bundleID))
        let running = tracker.appList
            .filter { $0.bundleID != nil && !existing.contains($0.bundleID!.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var seen = Set<String>()
        if !running.isEmpty {
            let header = NSMenuItem(title: "Running Applications", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for app in running {
            guard let bundleID = app.bundleID, seen.insert(bundleID.lowercased()).inserted else { continue }
            let item = ClosureMenuItem(app.name) { [weak self] in self?.add(bundleID: bundleID) }
            let icon = app.bundlePath.map { IconCache.shared.icon(path: $0) } ?? NSImage()
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !running.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Choose Application…") { [weak self] in
            Form.chooseApplication { url in
                if let bundleID = Form.appDetails(url: url).bundleID { self?.add(bundleID: bundleID) }
            }
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addButton.bounds.height + 4), in: addButton)
    }

    private func add(bundleID: String) {
        store.update { $0.grouping.setMode(.ungrouped, for: bundleID) }
    }

    @objc private func removeRule() {
        let row = table.selectedRow
        guard row >= 0, row < rules.count else { return }
        let bundleID = rules[row].bundleID
        store.update { $0.grouping.setMode(nil, for: bundleID) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = rules[row]
        if tableColumn?.identifier.rawValue == "mode" {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Group", "Separate"])
            popup.selectItem(at: rule.mode == .grouped ? 0 : 1)
            popup.controlSize = .small
            popup.tag = row
            popup.target = self
            popup.action = #selector(modeChanged(_:))
            return popup
        }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID)
        let name = url.map { Form.appDetails(url: $0).name } ?? rule.bundleID
        let icon = url.map { IconCache.shared.icon(path: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
        return Form.appCell(icon: icon, title: name, subtitle: rule.bundleID)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard sender.tag < rules.count else { return }
        let bundleID = rules[sender.tag].bundleID
        let mode: GroupingMode = sender.indexOfSelectedItem == 1 ? .ungrouped : .grouped
        store.update { $0.grouping.setMode(mode, for: bundleID) }
    }
}

final class PinnedPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: SettingsStore
    private let table = NSTableView()

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("app"))
        column.title = "Pinned applications"
        column.width = 520
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 230).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 556).isActive = true

        let buttons = NSStackView(views: [
            button("plus", "Add application", #selector(add)),
            button("minus", "Remove", #selector(remove)),
            button("line.3.horizontal", "Add separator", #selector(addSeparator)),
            button("chevron.up", "Move up", #selector(movePinUp)),
            button("chevron.down", "Move down", #selector(movePinDown)),
        ])
        buttons.spacing = 0
        view = Form.page([
            scroll,
            buttons,
            Form.note("Pinned apps stay in the dock when they are not running; click one to launch it. Drag apps from Finder onto the dock to pin them. Dragging a pinned app or separator saves its new position; dragging any other app keeps its position until Dockerd quits."),
        ])
        store.observe { [weak self] _, _ in self?.table.reloadData() }
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .smallSquare
        button.toolTip = label
        return button
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.settings.pinned.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pin = store.settings.pinned[row]
        if pin.isSeparator {
            let icon = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil) ?? NSImage()
            return Form.appCell(icon: icon, title: "Separator", subtitle: nil)
        }
        let exists = FileManager.default.fileExists(atPath: pin.path)
        return Form.appCell(icon: IconCache.shared.icon(path: pin.path), title: pin.name, subtitle: exists ? pin.path : "Missing: \(pin.path)")
    }

    @objc private func add() {
        Form.chooseApplication { [weak self] url in
            let details = Form.appDetails(url: url)
            self?.store.update { $0.pin(PinnedApp(bundleID: details.bundleID, path: url.path, name: details.name)) }
        }
    }

    @objc private func addSeparator() {
        let row = table.selectedRow
        let index = row >= 0 ? row + 1 : nil
        store.update { $0.pin(.separator(), at: index) }
    }

    @objc private func remove() {
        let row = table.selectedRow
        guard row >= 0, row < store.settings.pinned.count else { return }
        let key = store.settings.pinned[row].key
        store.update { $0.unpin(key: key) }
    }

    @objc private func movePinUp() { move(by: -1) }
    @objc private func movePinDown() { move(by: 1) }

    private func move(by delta: Int) {
        let row = table.selectedRow
        let pins = store.settings.pinned
        guard row >= 0, row < pins.count else { return }
        let target = min(max(row + delta, 0), pins.count - 1)
        store.update { $0.movePin(key: pins[row].key, to: target) }
        table.selectRowIndexes([target], byExtendingSelection: false)
    }
}

final class DisplaysPane: NSViewController {
    private let store: SettingsStore
    private let mode = NSPopUpButton()
    private let placement = NSPopUpButton()
    private var currentSpace: NSButton!
    private let displayList = NSStackView()
    private var screenToken: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        mode.addItems(withTitles: ["Every display", "Main display only", "Selected displays"])
        mode.target = self
        mode.action = #selector(changed)
        placement.addItems(withTitles: ["On the display the window is on", "On every dock (duplicates)"])
        placement.target = self
        placement.action = #selector(changed)
        currentSpace = Form.checkbox("Only show windows from the current Space", target: self, action: #selector(changed))
        displayList.orientation = .vertical
        displayList.alignment = .leading
        displayList.spacing = 6

        view = Form.page([
            Form.grid([
                ("Show a dock on", mode),
                ("", displayList),
                ("Show window entries", placement),
                ("", currentSpace),
            ]),
            Form.note("Space awareness is best-effort: macOS has no public API that says which Space a window belongs to. Dockerd treats a window as being on another Space when it exists but is not on screen and not minimized, and dims it. Windows that an app only reports on the active Space appear once you visit that Space."),
        ])
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        store.observe { [weak self] _, _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let d = store.settings.displays
        mode.selectItem(at: DockDisplayMode.allCases.firstIndex(of: d.mode) ?? 0)
        placement.selectItem(at: d.placement == .ownDisplay ? 0 : 1)
        currentSpace.state = d.currentSpaceOnly ? .on : .off
        displayList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        displayList.isHidden = d.mode != .selected
        for display in DockController.currentDisplays() {
            let box = NSButton(checkboxWithTitle: display.name + (display.isPrimary ? " (main)" : ""), target: self, action: #selector(displayToggled(_:)))
            box.identifier = NSUserInterfaceItemIdentifier(display.uuid)
            box.state = d.selectedDisplayUUIDs.contains(display.uuid) ? .on : .off
            displayList.addArrangedSubview(box)
        }
    }

    @objc private func changed() {
        store.update { s in
            s.displays.mode = DockDisplayMode.allCases[max(mode.indexOfSelectedItem, 0)]
            s.displays.placement = placement.indexOfSelectedItem == 1 ? .everyDisplay : .ownDisplay
            s.displays.currentSpaceOnly = currentSpace.state == .on
            if s.displays.mode == .selected && s.displays.selectedDisplayUUIDs.isEmpty,
               let primary = DockController.currentDisplays().first(where: \.isPrimary) {
                s.displays.selectedDisplayUUIDs = [primary.uuid]
            }
        }
    }

    @objc private func displayToggled(_ sender: NSButton) {
        guard let uuid = sender.identifier?.rawValue else { return }
        store.update { s in
            var selected = Set(s.displays.selectedDisplayUUIDs)
            if sender.state == .on { selected.insert(uuid) } else { selected.remove(uuid) }
            s.displays.selectedDisplayUUIDs = selected.sorted()
        }
    }
}

final class PermissionsPane: NSViewController {
    private let permissions: PermissionController
    private let store: SettingsStore
    private let status = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private var hideDock: NSButton!

    init(permissions: PermissionController, store: SettingsStore) {
        self.permissions = permissions
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        status.font = .systemFont(ofSize: 13, weight: .medium)
        let statusRow = NSStackView(views: [statusIcon, status])
        statusRow.spacing = 6
        let request = NSButton(title: "Request Access…", target: self, action: #selector(request))
        let open = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        let buttons = NSStackView(views: [request, open])
        buttons.spacing = 8

        hideDock = Form.checkbox("Hide the system Dock while Dockerd is running", target: self, action: #selector(hideDockChanged))
        let dockOpen = NSButton(title: "Open Desktop & Dock Settings", target: self, action: #selector(openDockSettings))
        let copyRestore = NSButton(title: "Copy “restore” command", target: self, action: #selector(copyRestore))
        let dockButtons = NSStackView(views: [dockOpen, copyRestore])
        dockButtons.spacing = 8

        view = Form.page([
            Form.header("Accessibility"),
            statusRow,
            Form.note("Dockerd needs Accessibility access to list windows, read their titles, and raise, minimize or close them. It does not capture the screen, read document contents, or use the network. If access stops working after an update, remove Dockerd from the list in System Settings and add it again."),
            buttons,
            Form.header("The system Dock"),
            hideDock,
            Form.note("Turns on Dock auto-hide with a very long delay and restarts the Dock. Your previous Dock settings are saved and put back when you turn this off or quit Dockerd. If Dockerd ever stops unexpectedly with the Dock hidden, open Dockerd again and turn this off, or run the restore command in Terminal."),
            dockButtons,
        ])
        permissions.observe { [weak self] _ in self?.refresh() }
        store.observe { [weak self] _, _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let granted = permissions.state.isGranted
        status.stringValue = granted ? "Accessibility access is allowed" : "Accessibility access is not allowed"
        statusIcon.image = NSImage(
            systemSymbolName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil)
        statusIcon.contentTintColor = granted ? .systemGreen : .systemOrange
        hideDock.state = store.settings.systemDock.hideWhileRunning ? .on : .off
    }

    @objc private func hideDockChanged() {
        let hide = hideDock.state == .on
        store.update { $0.systemDock.hideWhileRunning = hide }
    }

    @objc private func request() { permissions.requestAccess() }
    @objc private func openSettings() { permissions.openSystemSettings() }

    @objc private func openDockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyRestore() {
        copy(SystemDockCommands.restore)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum SystemDockCommands {
    static let restore = "defaults delete com.apple.dock autohide-delay; defaults delete com.apple.dock autohide; killall Dock"
}
