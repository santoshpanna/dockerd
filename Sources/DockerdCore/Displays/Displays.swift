import CoreGraphics
import Foundation

public struct DisplayInfo: Identifiable, Hashable, Sendable {
    public var id: UInt32
    public var uuid: String
    public var name: String
    public var frame: CGRect
    public var isPrimary: Bool

    public init(id: UInt32, uuid: String, name: String, frame: CGRect, isPrimary: Bool) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
    }
}

public enum DisplayGeometry {
    public static func topLeftRect(fromCocoa rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

public enum WindowDisplayAssigner {
    public static func display(for frame: CGRect?, among displays: [DisplayInfo]) -> DisplayInfo? {
        guard !displays.isEmpty else { return nil }
        let fallback = displays.first(where: \.isPrimary) ?? displays[0]
        guard let frame, frame.width > 0, frame.height > 0 else { return fallback }

        var best: DisplayInfo?
        var bestArea: CGFloat = 0
        for display in displays {
            let overlap = display.frame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = display
            }
        }
        if let best { return best }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.min { lhs, rhs in
            squaredDistance(center, lhs.frame) < squaredDistance(center, rhs.frame)
        } ?? fallback
    }

    static func squaredDistance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

public enum DockDisplaySelector {
    public static func dockDisplays(all displays: [DisplayInfo], settings: DisplaySettings) -> [DisplayInfo] {
        guard !displays.isEmpty else { return [] }
        let primary = displays.first(where: \.isPrimary) ?? displays[0]
        switch settings.mode {
        case .all:
            return displays
        case .primary:
            return [primary]
        case .selected:
            let chosen = displays.filter { settings.selectedDisplayUUIDs.contains($0.uuid) }
            return chosen.isEmpty ? [primary] : chosen
        }
    }
}

public struct DockMetrics: Equatable, Sendable {
    public var iconSize: CGFloat
    public var spacing: CGFloat
    public var titleWidth: CGFloat
    public var showTitles: Bool
    public var edge: DockEdge

    public static let itemPadding: CGFloat = 3
    public static let barPadding: CGFloat = 5
    public static let indicatorSpace: CGFloat = 6
    public static let minimumScale: CGFloat = 0.4
    public static let separatorExtent: CGFloat = 9

    public init(appearance: AppearanceSettings) {
        iconSize = CGFloat(appearance.iconSize)
        spacing = CGFloat(appearance.spacing)
        titleWidth = CGFloat(appearance.titleWidth)
        showTitles = appearance.showWindowTitles
        edge = appearance.edge
    }

    public var titlesVisible: Bool { showTitles && edge.isHorizontal }

    public var thickness: CGFloat {
        iconSize + Self.itemPadding * 2 + Self.indicatorSpace + Self.barPadding * 2
    }

    public func extent(of item: DockItem) -> CGFloat {
        if item.kind == .separator { return Self.separatorExtent }
        let base = iconSize + Self.itemPadding * 2
        if item.kind == .window && titlesVisible { return base + titleWidth }
        return base
    }

    public func contentLength(_ items: [DockItem], scale: CGFloat = 1) -> CGFloat {
        guard !items.isEmpty else { return Self.barPadding * 2 + iconSize }
        let sum = items.reduce(0) { $0 + extent(of: $1) } * scale
        return sum + spacing * CGFloat(items.count - 1) + Self.barPadding * 2
    }

    public func scale(toFit items: [DockItem], available: CGFloat) -> CGFloat {
        let full = contentLength(items)
        guard full > available, full > 0 else { return 1 }
        let fixed = spacing * CGFloat(max(items.count - 1, 0)) + Self.barPadding * 2
        let variable = full - fixed
        guard variable > 0 else { return 1 }
        return max(Self.minimumScale, (available - fixed) / variable)
    }
}

public enum DockGeometry {
    public static func availableLength(screenFrame: CGRect, visibleFrame: CGRect, edge: DockEdge) -> CGFloat {
        edge.isHorizontal ? screenFrame.width : visibleFrame.maxY - screenFrame.minY
    }

    public static func panelFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        edge: DockEdge,
        length: CGFloat,
        thickness: CGFloat
    ) -> CGRect {
        let available = availableLength(screenFrame: screenFrame, visibleFrame: visibleFrame, edge: edge)
        let extent = min(length, available)
        switch edge {
        case .bottom:
            return CGRect(
                x: (screenFrame.midX - extent / 2).rounded(),
                y: screenFrame.minY,
                width: extent,
                height: thickness)
        case .left, .right:
            return CGRect(
                x: edge == .left ? screenFrame.minX : screenFrame.maxX - thickness,
                y: (screenFrame.minY + (available - extent) / 2).rounded(),
                width: thickness,
                height: extent)
        }
    }

    public static func triggerFrame(screenFrame: CGRect, edge: DockEdge, depth: CGFloat = 2) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: depth)
        case .left:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: depth, height: screenFrame.height)
        case .right:
            return CGRect(x: screenFrame.maxX - depth, y: screenFrame.minY, width: depth, height: screenFrame.height)
        }
    }
}

public enum FullScreenCandidates {
    public static let minimumHeightFraction: CGFloat = 0.9

    public static func find(windows: [WindowInfo], displays: [DisplayInfo]) -> [(window: WindowID, display: UInt32)] {
        var result: [(window: WindowID, display: UInt32)] = []
        for window in windows where window.presence == .onScreen {
            guard let frame = window.frame else { continue }
            for display in displays {
                let screen = display.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                guard screen.contains(center),
                      frame.width >= screen.width - 1,
                      frame.height >= screen.height * minimumHeightFraction
                else { continue }
                result.append((window.id, display.id))
            }
        }
        return result
    }
}
