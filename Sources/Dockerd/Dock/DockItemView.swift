import AppKit
import DockerdCore

protocol DockItemViewDelegate: AnyObject {
    func dockItemClicked(_ view: DockItemView)
    func dockItemMenu(_ view: DockItemView) -> NSMenu?
    func dockItemHoverChanged(_ view: DockItemView, hovering: Bool)
    func dockItemCanDrag(_ view: DockItemView) -> Bool
}

final class DockItemView: NSView, NSDraggingSource {
    weak var delegate: DockItemViewDelegate?
    private(set) var item: DockItem
    private var metrics: DockMetrics
    private var scale: CGFloat
    private var hovering = false
    private var pressed = false
    private var mouseDownPoint: NSPoint?
    private var dragStarted = false
    private var trackingArea: NSTrackingArea?

    var tooltipsEnabled = true {
        didSet { if oldValue != tooltipsEnabled { updateAccessibility() } }
    }

    var isKeyboardFocused = false {
        didSet { if oldValue != isKeyboardFocused { needsDisplay = true } }
    }

    init(item: DockItem, metrics: DockMetrics, scale: CGFloat) {
        self.item = item
        self.metrics = metrics
        self.scale = scale
        super.init(frame: .zero)
        wantsLayer = true
        updateAccessibility()
        updateLaunchAnimation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(item: DockItem, metrics: DockMetrics, scale: CGFloat) {
        guard item != self.item || metrics != self.metrics || scale != self.scale else { return }
        self.item = item
        self.metrics = metrics
        self.scale = scale
        updateAccessibility()
        updateLaunchAnimation()
        needsDisplay = true
    }

    private static let launchAnimationKey = "launching"

    private func updateLaunchAnimation() {
        guard let layer else { return }
        let running = layer.animation(forKey: Self.launchAnimationKey) != nil
        if item.isLaunching && !running {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.35
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            layer.add(pulse, forKey: Self.launchAnimationKey)
        } else if !item.isLaunching && running {
            layer.removeAnimation(forKey: Self.launchAnimationKey)
        }
    }

    var iconSide: CGFloat { (metrics.iconSize * scale).rounded() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
        delegate?.dockItemHoverChanged(self, hovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
        delegate?.dockItemHoverChanged(self, hovering: false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
            return
        }
        pressed = true
        dragStarted = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !dragStarted, delegate?.dockItemCanDrag(self) == true else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 5 else { return }
        dragStarted = true
        pressed = false
        delegate?.dockItemHoverChanged(self, hovering: false)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.appKey, forType: .dockerdItem)
        if item.kind == .window, let window = item.windows.first {
            pasteboardItem.setString(String(window.id.rawValue), forType: .dockerdWindow)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = IconCache.shared.icon(for: item)
        let side = iconSide
        draggingItem.setDraggingFrame(NSRect(x: start.x - side / 2, y: start.y - side / 2, width: side, height: side), contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressed = false
            mouseDownPoint = nil
            needsDisplay = true
        }
        guard !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { delegate?.dockItemClicked(self) }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    private func showMenu(with event: NSEvent) {
        delegate?.dockItemHoverChanged(self, hovering: false)
        guard let menu = delegate?.dockItemMenu(self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragStarted = false
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if item.kind == .separator {
            drawSeparator()
            return
        }
        let highlight: NSColor?
        if pressed {
            highlight = NSColor.labelColor.withAlphaComponent(0.22)
        } else if item.isFocusedWindow || (item.kind == .application && item.isActive) {
            highlight = NSColor.labelColor.withAlphaComponent(0.14)
        } else if hovering {
            highlight = NSColor.labelColor.withAlphaComponent(0.08)
        } else {
            highlight = nil
        }
        let plate = bounds.insetBy(dx: 1, dy: 2)
        if let highlight {
            highlight.setFill()
            NSBezierPath(roundedRect: plate, xRadius: 9, yRadius: 9).fill()
        }
        if isKeyboardFocused {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: plate.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            ring.stroke()
        }

        let side = iconSide
        let padding = DockMetrics.itemPadding * scale
        let iconRect: NSRect
        if metrics.titlesVisible && item.kind == .window {
            iconRect = NSRect(x: padding, y: (bounds.height - side) / 2 - 2, width: side, height: side)
        } else {
            iconRect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2 - (metrics.edge.isHorizontal ? 2 : 0), width: side, height: side)
        }
        let window = item.window
        let dimmed = window?.presence == .minimized || window?.presence == .otherSpace || item.isHidden
            || (item.kind == .application && !item.windows.isEmpty && item.windows.allSatisfy { $0.presence != .onScreen })
        IconCache.shared.icon(for: item).draw(
            in: iconRect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.5 : 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

        if window?.presence == .minimized {
            drawBadgeSymbol("arrow.down.right.and.arrow.up.left", near: iconRect)
        } else if window?.presence == .otherSpace {
            drawBadgeSymbol("rectangle.on.rectangle", near: iconRect)
        }

        if item.kind == .application && item.windows.count > 1 {
            drawCountBadge(item.windows.count, near: iconRect)
        }

        if let badge = item.badge {
            drawNotificationBadge(badge, near: iconRect)
        }

        if metrics.titlesVisible && item.kind == .window {
            let textX = iconRect.maxX + 5
            let textRect = NSRect(x: textX, y: 0, width: max(bounds.width - textX - padding, 0), height: bounds.height - 4)
            drawTitle(item.title, in: textRect, dimmed: dimmed)
        }

        if item.isRunning {
            drawIndicator(iconRect: iconRect)
        }
    }

    private func drawTitle(_ title: String, in rect: NSRect, dimmed: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: max(10, min(13, metrics.iconSize * scale * 0.3)), weight: item.isFocusedWindow ? .semibold : .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let height = font.boundingRectForFont.height
        let textRect = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        (title as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    private func drawSeparator() {
        let inset = bounds.insetBy(dx: 4, dy: 4)
        let line: NSRect
        if metrics.edge.isHorizontal {
            line = NSRect(x: bounds.midX - 0.5, y: inset.minY + 4, width: 1, height: max(inset.height - 8, 0))
        } else {
            line = NSRect(x: inset.minX + 4, y: bounds.midY - 0.5, width: max(inset.width - 8, 0), height: 1)
        }
        NSColor.labelColor.withAlphaComponent(pressed || isKeyboardFocused ? 0.6 : 0.3).setFill()
        line.fill()
    }

    private func drawIndicator(iconRect: NSRect) {
        let size: CGFloat = 4
        let center: NSPoint
        switch metrics.edge {
        case .bottom: center = NSPoint(x: iconRect.midX, y: bounds.maxY - 4)
        case .left: center = NSPoint(x: 3, y: iconRect.midY)
        case .right: center = NSPoint(x: bounds.maxX - 3, y: iconRect.midY)
        }
        let color: NSColor = item.isActive ? .controlAccentColor : .labelColor.withAlphaComponent(0.55)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)).fill()
    }

    private func drawCountBadge(_ count: Int, near iconRect: NSRect) {
        let text = count > 99 ? "99+" : "\(count)"
        drawPill(text, fill: NSColor.darkGray.withAlphaComponent(0.9), size: 9, height: 14, near: iconRect, top: false)
    }

    private func drawNotificationBadge(_ label: String, near iconRect: NSRect) {
        let text = label.count > 4 ? String(label.prefix(3)) + "…" : label
        drawPill(text, fill: .systemRed, size: 10, height: 16, near: iconRect, top: true)
    }

    private func drawPill(_ text: String, fill: NSColor, size: CGFloat, height: CGFloat, near iconRect: NSRect, top: Bool) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let width = max(height, textSize.width + 8)
        let y = top ? iconRect.minY - 3 : iconRect.maxY - height + 3
        let rect = NSRect(x: iconRect.maxX - width + 4, y: y, width: width, height: height)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        (text as NSString).draw(
            at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes)
    }

    private func drawBadgeSymbol(_ name: String, near iconRect: NSRect) {
        let side = max(12, iconSide * 0.36)
        let rect = NSRect(x: iconRect.maxX - side + 3, y: iconRect.maxY - side + 3, width: side, height: side)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.55, weight: .bold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSColor.secondaryLabelColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(
            in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(item.kind == .separator ? .splitter : .button)
        setAccessibilityLabel(DockItemDescriber.accessibilityLabel(for: item))
        setAccessibilityHelp(DockItemDescriber.help(for: item))
        toolTip = tooltipsEnabled && item.kind != .separator ? DockItemDescriber.tooltip(for: item) : nil
    }

    override func accessibilityPerformPress() -> Bool {
        delegate?.dockItemClicked(self)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = delegate?.dockItemMenu(self) else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        return true
    }
}

enum DockItemDescriber {
    static func state(of window: WindowInfo) -> String? {
        switch window.presence {
        case .minimized: return "Minimized"
        case .hidden: return "Hidden"
        case .otherSpace: return "On another Space"
        case .onScreen: return nil
        }
    }

    static func accessibilityLabel(for item: DockItem) -> String {
        var parts: [String] = []
        switch item.kind {
        case .accessibilityNotice, .separator, .downloads, .trash:
            parts = [item.appName]
        case .launcher:
            parts = [item.appName, item.isLaunching ? "launching" : "not running"]
        case .application:
            parts = [item.appName]
            if item.windows.count == 1 { parts.append("1 window") }
            if item.windows.count > 1 { parts.append("\(item.windows.count) windows") }
            if item.isActive { parts.append("active") }
        case .window:
            parts = [item.title, item.appName]
            if let window = item.window, let state = state(of: window) { parts.append(state) }
            if item.isFocusedWindow { parts.append("focused") }
        }
        if item.isHidden { parts.append("hidden") }
        if let badge = item.badge { parts.append("badge \(badge)") }
        return parts.joined(separator: ", ")
    }

    static func tooltip(for item: DockItem) -> String {
        switch item.kind {
        case .separator, .downloads, .trash: return item.appName
        case .accessibilityNotice: return "Dockerd can't see windows until it has Accessibility access. Click to fix."
        case .launcher: return item.appName
        case .application:
            return item.windows.count > 1 ? "\(item.appName) — \(item.windows.count) windows" : item.appName
        case .window:
            guard let window = item.window else { return item.appName }
            let state = state(of: window).map { " (\($0))" } ?? ""
            return "\(window.displayTitle) — \(item.appName)\(state)"
        }
    }

    static func help(for item: DockItem) -> String {
        switch item.kind {
        case .downloads: return "Shows recent downloads"
        case .trash: return "Opens the Trash"
        case .separator: return item.isPinned ? "Drag to move, or open the menu to remove" : "Separates pinned apps from other apps"
        case .accessibilityNotice: return "Shows how to grant Accessibility access"
        case .launcher: return "Opens \(item.appName)"
        case .application: return item.windows.count > 1 ? "Shows the window list" : "Activates \(item.appName)"
        case .window: return "Activates this window"
        }
    }
}
