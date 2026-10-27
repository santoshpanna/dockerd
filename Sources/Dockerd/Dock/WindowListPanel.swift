import AppKit
import DockerdCore

protocol WindowListPanelDelegate: AnyObject {
    func windowList(_ panel: WindowListPanel, activate window: WindowInfo)
    func windowList(_ panel: WindowListPanel, menuFor window: WindowInfo) -> NSMenu?
    func windowList(_ panel: WindowListPanel, close window: WindowInfo)
}

final class WindowListPanel: CardPanel {
    weak var listDelegate: WindowListPanelDelegate?
    private let stack = NSStackView()
    private let header = NSTextField(labelWithString: "")
    private var monitors: [Any] = []
    private(set) var itemID: String?
    private var lastDismissal: (id: String, at: Date)?
    private var anchor: NSRect = .zero
    private var edge: DockEdge = .bottom

    init() {
        super.init(cornerRadius: 12)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        setAccessibilityRole(.list)
    }

    func present(item: DockItem, anchor: NSRect, edge: DockEdge) {
        self.anchor = anchor
        self.edge = edge
        reload(item: item)
        orderFrontRegardless()
        installMonitors()
    }

    func reload(item: DockItem) {
        itemID = item.id
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        header.stringValue = item.appName.uppercased()
        let headerBox = NSStackView(views: [header])
        headerBox.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 4, right: 8)
        stack.addArrangedSubview(headerBox)
        let width: CGFloat = 320
        for window in item.windows {
            let row = WindowRowView(window: window, icon: IconCache.shared.icon(for: item), isActiveApp: item.isActive)
            row.onActivate = { [weak self] in
                guard let self else { return }
                self.listDelegate?.windowList(self, activate: window)
            }
            row.onClose = { [weak self] in
                guard let self else { return }
                self.listDelegate?.windowList(self, close: window)
            }
            row.menuProvider = { [weak self] in
                guard let self else { return nil }
                return self.listDelegate?.windowList(self, menuFor: window)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: width - 12).isActive = true
        }
        setAccessibilityLabel("\(item.appName) windows")
        contentView?.layoutSubtreeIfNeeded()
        let height = min(stack.fittingSize.height, (NSScreen.main?.visibleFrame.height ?? 800) * 0.7)
        place(size: NSSize(width: width, height: height), anchor: anchor, edge: edge)
    }

    func wasJustDismissed(itemID: String) -> Bool {
        guard let lastDismissal, lastDismissal.id == itemID else { return false }
        return Date().timeIntervalSince(lastDismissal.at) < 0.4
    }

    func dismiss() {
        removeMonitors()
        if let itemID, isVisible { lastDismissal = (itemID, Date()) }
        itemID = nil
        orderOut(nil)
    }

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let self, event.window !== self { self.dismiss() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

private final class WindowRowView: NSView {
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private let windowInfo: WindowInfo
    private let isActiveApp: Bool
    private var hovering = false
    private let closeButton: NSButton
    private var area: NSTrackingArea?

    init(window: WindowInfo, icon: NSImage, isActiveApp: Bool) {
        self.windowInfo = window
        self.isActiveApp = isActiveApp
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close window") ?? NSImage(), target: nil, action: nil)
        super.init(frame: .zero)
        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: window.displayTitle)
        title.lineBreakMode = .byTruncatingMiddle
        title.font = .systemFont(ofSize: 13, weight: window.isFocused && isActiveApp ? .semibold : .regular)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let state = DockItemDescriber.state(of: window)
        let detail = NSTextField(labelWithString: state ?? "")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.isHidden = state == nil
        if state != nil { title.textColor = .secondaryLabelColor }
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        closeButton.toolTip = "Close window"

        let row = NSStackView(views: [iconView, title, NSView(), detail, closeButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel([window.displayTitle, state].compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        closeButton.isHidden = false
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        closeButton.isHidden = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    @objc private func closeTapped() {
        onClose?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
}
