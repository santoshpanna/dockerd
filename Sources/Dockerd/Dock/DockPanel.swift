import AppKit
import DockerdCore

final class DockPanel: NSPanel {
    var allowsKey = false
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Dockerd")
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

final class EdgeTriggerPanel: NSPanel {
    var onEnter: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let view = TriggerView()
        view.onEnter = { [weak self] in self?.onEnter?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TriggerView: NSView {
    var onEnter: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}

final class DockPanelController {
    let display: DisplayInfo
    let panel = DockPanel()
    let bar: DockBarView
    private let effectView = NSVisualEffectView()
    private let border = BorderView()
    private let trigger = EdgeTriggerPanel()
    private var items: [DockItem] = []
    private var appearance = AppearanceSettings()
    private var metrics: DockMetrics
    private var visible = false
    private var revealed = false
    private var fullScreen = false
    private var autoHides: Bool { appearance.autoHide || fullScreen }
    private var hideTimer: Timer?
    private var hideDeadline: Date?
    var isInteractionLocked: () -> Bool = { false }

    init(display: DisplayInfo, delegate: DockBarViewDelegate) {
        self.display = display
        metrics = DockMetrics(appearance: appearance)
        bar = DockBarView(metrics: metrics)
        bar.delegate = delegate

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        border.radius = 16

        let root = NSView()
        for view in [effectView, bar, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.topAnchor.constraint(equalTo: root.topAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        panel.contentView = root
        trigger.onEnter = { [weak self] in self?.reveal() }
    }

    var screen: NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id }
    }

    func update(items: [DockItem], appearance: AppearanceSettings, visible: Bool, fullScreen: Bool) {
        let appearanceChanged = appearance != self.appearance || fullScreen != self.fullScreen
        self.fullScreen = fullScreen
        self.items = items
        self.appearance = appearance
        self.visible = visible
        metrics = DockMetrics(appearance: appearance)
        bar.showsTooltips = !appearance.showHoverPreviews
        relayout()
        if appearanceChanged && autoHides { revealed = false }
        applyVisibility(animated: false)
    }

    func relayout() {
        guard let screen else { return }
        let available = DockGeometry.availableLength(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, edge: metrics.edge)
        let scale = metrics.scale(toFit: items, available: available)
        let length = metrics.contentLength(items, scale: scale)
        let frame = DockGeometry.panelFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, edge: metrics.edge, length: length, thickness: metrics.thickness)
        bar.setItems(items, metrics: metrics, scale: scale)
        if border.flatEdge != metrics.edge {
            effectView.maskImage = DockImages.roundedMask(radius: 16, flatEdge: metrics.edge)
            border.flatEdge = metrics.edge
            border.needsDisplay = true
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        trigger.setFrame(DockGeometry.triggerFrame(screenFrame: screen.frame, edge: metrics.edge), display: false)
    }

    private func applyVisibility(animated: Bool) {
        let shouldShow = visible && (!autoHides || revealed || isInteractionLocked())
        if shouldShow {
            if !panel.isVisible || panel.alphaValue < 1 {
                panel.alphaValue = animated ? 0 : 1
                panel.orderFrontRegardless()
                if animated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.15
                        panel.animator().alphaValue = 1
                    }
                }
            }
        } else if panel.isVisible {
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.revealed || !self.visible else { return }
                        self.panel.orderOut(nil)
                    }
                })
            } else {
                panel.orderOut(nil)
            }
        }
        if visible && autoHides {
            trigger.orderFrontRegardless()
        } else {
            trigger.orderOut(nil)
        }
        if shouldShow && autoHides { startHideTimer() } else { stopHideTimer() }
    }

    func reveal() {
        guard visible, autoHides else { return }
        hideDeadline = nil
        revealed = true
        applyVisibility(animated: true)
    }

    func close() {
        stopHideTimer()
        panel.orderOut(nil)
        trigger.orderOut(nil)
    }

    private func startHideTimer() {
        guard hideTimer == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHide() }
        }
    }

    private func stopHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
        hideDeadline = nil
    }

    private func checkHide() {
        let mouse = NSEvent.mouseLocation
        let zone = panel.frame.insetBy(dx: -12, dy: -12).union(trigger.frame)
        if zone.contains(mouse) || isInteractionLocked() || panel.isKeyWindow {
            hideDeadline = nil
            return
        }
        let now = Date()
        guard let deadline = hideDeadline else {
            hideDeadline = now.addingTimeInterval(appearance.autoHideDelay)
            return
        }
        if now >= deadline {
            revealed = false
            stopHideTimer()
            applyVisibility(animated: true)
        }
    }
}
