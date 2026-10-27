import AppKit
import DockerdCore

final class HoverCard: CardPanel {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?
    private(set) var itemID: String?

    init() {
        super.init(cornerRadius: 10)
        ignoresMouseEvents = true
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        titleLabel.preferredMaxLayoutWidth = 280
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [iconView, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            row.topAnchor.constraint(equalTo: effectView.topAnchor),
            row.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
    }

    func schedule(item: DockItem, anchor: NSRect, edge: DockEdge, delay: TimeInterval = 0.45) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.show(item: item, anchor: anchor, edge: edge) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isVisible ? 0.05 : delay), execute: work)
    }

    func dismiss() {
        pending?.cancel()
        pending = nil
        itemID = nil
        orderOut(nil)
    }

    private func show(item: DockItem, anchor: NSRect, edge: DockEdge) {
        itemID = item.id
        iconView.image = IconCache.shared.icon(for: item)
        titleLabel.stringValue = item.title
        detailLabel.stringValue = Self.detail(for: item)
        contentView?.layoutSubtreeIfNeeded()
        let size = contentView?.fittingSize ?? NSSize(width: 220, height: 56)
        place(size: NSSize(width: max(size.width, 160), height: size.height), anchor: anchor, edge: edge)
        orderFrontRegardless()
    }

    static func detail(for item: DockItem) -> String {
        switch item.kind {
        case .separator:
            return ""
        case .downloads:
            return "Click for recent downloads"
        case .trash:
            return "Click to open · right-click to empty"
        case .accessibilityNotice:
            return "Windows can't be listed or grouped yet — click to fix"
        case .launcher:
            return "Not running — click to open"
        case .application:
            let count = item.windows.count
            var parts = [count == 0 ? "No windows" : (count == 1 ? "1 window" : "\(count) windows")]
            let minimized = item.windows.filter { $0.presence == .minimized }.count
            if minimized > 0 { parts.append("\(minimized) minimized") }
            if item.isHidden { parts.append("hidden") }
            return parts.joined(separator: " · ")
        case .window:
            var parts = [item.appName]
            if let window = item.window, let state = DockItemDescriber.state(of: window) { parts.append(state) }
            return parts.joined(separator: " · ")
        }
    }
}
