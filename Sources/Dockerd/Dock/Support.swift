import AppKit
import DockerdCore

extension NSPasteboard.PasteboardType {
    static let dockerdItem = NSPasteboard.PasteboardType("me.santoshpanna.dockerd.item")
    static let dockerdWindow = NSPasteboard.PasteboardType("me.santoshpanna.dockerd.window")
}

nonisolated final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        self.target = self
        self.state = state
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() {
        let handler = self.handler
        MainActor.assumeIsolated { handler() }
    }
}

enum AppActivation {
    static func bringSelfForward() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let generic = NSWorkspace.shared.icon(for: .application)
    private var trashCheckedAt = Date.distantPast
    private var trashFull = false

    private func trashIcon() -> NSImage {
        if Date().timeIntervalSince(trashCheckedAt) > 5 {
            trashFull = SystemFolders.trashIsEmpty() == false
            trashCheckedAt = Date()
        }
        return NSImage(named: trashFull ? NSImage.trashFullName : NSImage.trashEmptyName) ?? generic
    }

    private lazy var noticeIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, .systemOrange]))
        return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Accessibility access needed")?
            .withSymbolConfiguration(config) ?? generic
    }()

    func icon(for item: DockItem) -> NSImage {
        switch item.kind {
        case .accessibilityNotice: return noticeIcon
        case .downloads: return icon(path: SystemFolders.downloads.path)
        case .trash: return trashIcon()
        default: break
        }
        if let path = item.bundlePath { return icon(path: path) }
        if let pid = item.pids.first, let image = NSRunningApplication(processIdentifier: pid)?.icon {
            return image
        }
        return generic
    }

    func icon(path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }

    func icon(bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return generic }
        return icon(path: url.path)
    }
}

enum DockImages {
    static func roundedMask(radius: CGFloat, flatEdge: DockEdge? = nil) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: extend(rect, past: flatEdge, by: radius), xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    static func extend(_ rect: NSRect, past edge: DockEdge?, by amount: CGFloat) -> NSRect {
        switch edge {
        case .bottom: NSRect(x: rect.minX, y: rect.minY - amount, width: rect.width, height: rect.height + amount)
        case .left: NSRect(x: rect.minX - amount, y: rect.minY, width: rect.width + amount, height: rect.height)
        case .right: NSRect(x: rect.minX, y: rect.minY, width: rect.width + amount, height: rect.height)
        case nil: rect
        }
    }
}

final class BorderView: NSView {
    var radius: CGFloat = 14
    var flatEdge: DockEdge?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: DockImages.extend(bounds.insetBy(dx: 0.5, dy: 0.5), past: flatEdge, by: radius + 1), xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()
    }
}

class CardPanel: NSPanel {
    let effectView = NSVisualEffectView()
    let border = BorderView()
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = DockImages.roundedMask(radius: cornerRadius)
        border.radius = cornerRadius
        let root = NSView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        border.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(effectView)
        root.addSubview(border)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: root.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            border.topAnchor.constraint(equalTo: root.topAnchor),
            border.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(size: NSSize, anchor: NSRect, edge: DockEdge, gap: CGFloat = 8) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .left:
            origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        if let bounds = screen?.visibleFrame.insetBy(dx: 6, dy: 6) {
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
