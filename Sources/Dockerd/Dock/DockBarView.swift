import AppKit
import DockerdCore

protocol DockBarViewDelegate: DockItemViewDelegate {
    func dockBar(_ bar: DockBarView, moveItemWithKey key: String, windowID: WindowID?, toIndex index: Int)
    func dockBar(_ bar: DockBarView, dropApplicationAt url: URL, toIndex index: Int)
    func dockBarKeyboardExit(_ bar: DockBarView)
}

final class DockBarView: NSView {
    weak var delegate: DockBarViewDelegate?
    private(set) var itemViews: [DockItemView] = []
    private var metrics: DockMetrics
    private var scale: CGFloat = 1
    private var dropIndex: Int?
    private var focusedIndex: Int?
    var showsTooltips = true

    init(metrics: DockMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        registerForDraggedTypes([.dockerdItem, .fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Dockerd")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func setItems(_ items: [DockItem], metrics: DockMetrics, scale: CGFloat) {
        self.metrics = metrics
        self.scale = scale
        var existing = Dictionary(itemViews.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [DockItemView] = []
        for item in items {
            let view: DockItemView
            if let reused = existing.removeValue(forKey: item.id) {
                reused.update(item: item, metrics: metrics, scale: scale)
                view = reused
            } else {
                view = DockItemView(item: item, metrics: metrics, scale: scale)
                view.delegate = delegate
                addSubview(view)
            }
            view.tooltipsEnabled = showsTooltips
            next.append(view)
        }
        existing.values.forEach { $0.removeFromSuperview() }
        itemViews = next
        if let index = focusedIndex { focus(index: min(index, itemViews.count - 1)) }
        setAccessibilityChildren(itemViews)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let horizontal = metrics.edge.isHorizontal
        var cursor = DockMetrics.barPadding
        for view in itemViews {
            let extent = (metrics.extent(of: view.item) * scale).rounded()
            if horizontal {
                view.frame = NSRect(x: cursor, y: DockMetrics.barPadding, width: extent, height: bounds.height - DockMetrics.barPadding * 2)
            } else {
                view.frame = NSRect(x: DockMetrics.barPadding, y: cursor, width: bounds.width - DockMetrics.barPadding * 2, height: extent)
            }
            cursor += extent + metrics.spacing
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let dropIndex else { return }
        let horizontal = metrics.edge.isHorizontal
        let position: CGFloat
        if dropIndex < itemViews.count {
            let frame = itemViews[dropIndex].frame
            position = (horizontal ? frame.minX : frame.minY) - metrics.spacing / 2
        } else if let last = itemViews.last {
            position = (horizontal ? last.frame.maxX : last.frame.maxY) + metrics.spacing / 2
        } else {
            position = DockMetrics.barPadding
        }
        NSColor.controlAccentColor.setFill()
        let rect = horizontal
            ? NSRect(x: position - 1, y: DockMetrics.barPadding, width: 2, height: bounds.height - DockMetrics.barPadding * 2)
            : NSRect(x: DockMetrics.barPadding, y: position - 1, width: bounds.width - DockMetrics.barPadding * 2, height: 2)
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }

    private func insertionIndex(for point: NSPoint) -> Int {
        let horizontal = metrics.edge.isHorizontal
        let value = horizontal ? point.x : point.y
        for (index, view) in itemViews.enumerated() {
            let mid = horizontal ? view.frame.midX : view.frame.midY
            if value < mid { return index }
        }
        return itemViews.count
    }

    private func applicationURL(from info: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "app" }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = sender.draggingPasteboard.string(forType: .dockerdItem) != nil || applicationURL(from: sender) != nil
        guard accepts else { return [] }
        let index = insertionIndex(for: convert(sender.draggingLocation, from: nil))
        if index != dropIndex {
            dropIndex = index
            needsDisplay = true
        }
        return sender.draggingPasteboard.string(forType: .dockerdItem) != nil ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropIndex = nil
        needsDisplay = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropIndex = nil
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = insertionIndex(for: convert(sender.draggingLocation, from: nil))
        dropIndex = nil
        needsDisplay = true
        if let key = sender.draggingPasteboard.string(forType: .dockerdItem) {
            let windowID = sender.draggingPasteboard.string(forType: .dockerdWindow).flatMap(UInt64.init).map(WindowID.init)
            delegate?.dockBar(self, moveItemWithKey: key, windowID: windowID, toIndex: index)
            return true
        }
        if let url = applicationURL(from: sender) {
            delegate?.dockBar(self, dropApplicationAt: url, toIndex: index)
            return true
        }
        return false
    }

    func beginKeyboardFocus() {
        guard !itemViews.isEmpty else { return }
        window?.makeFirstResponder(self)
        focus(index: itemViews.firstIndex { $0.item.isActive } ?? focusable(from: 0, step: 1))
    }

    private func focusable(from index: Int, step: Int) -> Int {
        var candidate = index
        while candidate >= 0 && candidate < itemViews.count {
            if itemViews[candidate].item.kind != .separator { return candidate }
            candidate += step
        }
        return focusedIndex ?? min(max(index, 0), max(itemViews.count - 1, 0))
    }

    func endKeyboardFocus() {
        if let index = focusedIndex, index < itemViews.count { itemViews[index].isKeyboardFocused = false }
        focusedIndex = nil
    }

    private func focus(index: Int) {
        guard !itemViews.isEmpty else {
            focusedIndex = nil
            return
        }
        itemViews.forEach { $0.isKeyboardFocused = false }
        let clamped = min(max(index, 0), itemViews.count - 1)
        focusedIndex = clamped
        itemViews[clamped].isKeyboardFocused = true
        NSAccessibility.post(element: itemViews[clamped], notification: .focusedUIElementChanged)
    }

    override func keyDown(with event: NSEvent) {
        guard let index = focusedIndex else {
            super.keyDown(with: event)
            return
        }
        let horizontal = metrics.edge.isHorizontal
        switch Int(event.keyCode) {
        case 123 where horizontal, 126 where !horizontal:
            focus(index: focusable(from: index - 1, step: -1))
        case 124 where horizontal, 125 where !horizontal:
            focus(index: focusable(from: index + 1, step: 1))
        case 115:
            focus(index: focusable(from: 0, step: 1))
        case 119:
            focus(index: focusable(from: itemViews.count - 1, step: -1))
        case 36, 49, 76:
            let view = itemViews[index]
            delegate?.dockItemClicked(view)
        case 53:
            delegate?.dockBarKeyboardExit(self)
        default:
            if event.charactersIgnoringModifiers == "m" || (event.keyCode == 109 && event.modifierFlags.contains(.shift)) {
                let view = itemViews[index]
                if let menu = delegate?.dockItemMenu(view) {
                    menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
