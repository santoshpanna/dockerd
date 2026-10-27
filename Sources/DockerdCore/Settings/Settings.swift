import Foundation

public enum DockEdge: String, Codable, CaseIterable, Sendable {
    case bottom
    case left
    case right

    public var isHorizontal: Bool { self == .bottom }
}

public enum DockDisplayMode: String, Codable, CaseIterable, Sendable {
    case all
    case primary
    case selected
}

public enum WindowPlacement: String, Codable, CaseIterable, Sendable {
    case ownDisplay
    case everyDisplay
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public static let iconSizeRange: ClosedRange<Double> = 24...96
    public static let spacingRange: ClosedRange<Double> = 0...24
    public static let titleWidthRange: ClosedRange<Double> = 60...320
    public static let autoHideDelayRange: ClosedRange<Double> = 0...3

    public var edge: DockEdge = .bottom
    public var iconSize: Double = 44 { didSet { iconSize = iconSize.clamped(to: Self.iconSizeRange) } }
    public var spacing: Double = 2 { didSet { spacing = spacing.clamped(to: Self.spacingRange) } }
    public var showWindowTitles: Bool = true
    public var titleWidth: Double = 150 { didSet { titleWidth = titleWidth.clamped(to: Self.titleWidthRange) } }
    public var autoHide: Bool = false
    public var autoHideDelay: Double = 0.5 {
        didSet { autoHideDelay = autoHideDelay.clamped(to: Self.autoHideDelayRange) }
    }
    public var clickActiveWindowToMinimize: Bool = true
    public var showHoverPreviews: Bool = true
    public var separatorAfterPinned: Bool = false
    public var showDownloads: Bool = true
    public var showTrash: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case edge, iconSize, spacing, showWindowTitles, titleWidth, autoHide, autoHideDelay
        case clickActiveWindowToMinimize, showHoverPreviews, separatorAfterPinned, showDownloads, showTrash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceSettings()
        edge = c.value(.edge, d.edge)
        iconSize = c.value(.iconSize, d.iconSize).clamped(to: Self.iconSizeRange)
        spacing = c.value(.spacing, d.spacing).clamped(to: Self.spacingRange)
        showWindowTitles = c.value(.showWindowTitles, d.showWindowTitles)
        titleWidth = c.value(.titleWidth, d.titleWidth).clamped(to: Self.titleWidthRange)
        autoHide = c.value(.autoHide, d.autoHide)
        autoHideDelay = c.value(.autoHideDelay, d.autoHideDelay).clamped(to: Self.autoHideDelayRange)
        clickActiveWindowToMinimize = c.value(.clickActiveWindowToMinimize, d.clickActiveWindowToMinimize)
        showHoverPreviews = c.value(.showHoverPreviews, d.showHoverPreviews)
        separatorAfterPinned = c.value(.separatorAfterPinned, d.separatorAfterPinned)
        showDownloads = c.value(.showDownloads, d.showDownloads)
        showTrash = c.value(.showTrash, d.showTrash)
    }
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public var mode: DockDisplayMode = .all
    public var selectedDisplayUUIDs: [String] = []
    public var placement: WindowPlacement = .ownDisplay
    public var currentSpaceOnly: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case mode, selectedDisplayUUIDs, placement, currentSpaceOnly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplaySettings()
        mode = c.value(.mode, d.mode)
        selectedDisplayUUIDs = c.value(.selectedDisplayUUIDs, d.selectedDisplayUUIDs)
        placement = c.value(.placement, d.placement)
        currentSpaceOnly = c.value(.currentSpaceOnly, d.currentSpaceOnly)
    }
}

public struct SystemDockSettings: Codable, Equatable, Sendable {
    public var hideWhileRunning: Bool = false
    public var hiddenByDockerd: Bool = false
    public var savedAutohide: Bool?
    public var savedAutohideDelay: Double?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case hideWhileRunning, hiddenByDockerd, savedAutohide, savedAutohideDelay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideWhileRunning = c.value(.hideWhileRunning, false)
        hiddenByDockerd = c.value(.hiddenByDockerd, false)
        savedAutohide = try? c.decodeIfPresent(Bool.self, forKey: .savedAutohide)
        savedAutohideDelay = try? c.decodeIfPresent(Double.self, forKey: .savedAutohideDelay)
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var grouping = GroupingPolicy()
    public var pinned: [PinnedApp] = []
    public var appearance = AppearanceSettings()
    public var displays = DisplaySettings()
    public var dockVisible: Bool = true
    public var systemDock = SystemDockSettings()
    public var loginItemConfigured = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, grouping, pinned, appearance, displays, dockVisible, systemDock, loginItemConfigured
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = c.value(.schemaVersion, d.schemaVersion)
        grouping = c.value(.grouping, d.grouping)
        pinned = c.value(.pinned, d.pinned)
        appearance = c.value(.appearance, d.appearance)
        displays = c.value(.displays, d.displays)
        dockVisible = c.value(.dockVisible, d.dockVisible)
        systemDock = c.value(.systemDock, d.systemDock)
        loginItemConfigured = c.value(.loginItemConfigured, d.loginItemConfigured)
    }

    public func isPinned(_ app: AppInfo) -> Bool {
        pinned.contains { $0.matches(app) }
    }

    public mutating func pin(_ app: PinnedApp, at index: Int? = nil) {
        pinned.removeAll { $0.key == app.key }
        let target = min(max(index ?? pinned.count, 0), pinned.count)
        pinned.insert(app, at: target)
    }

    public mutating func unpin(key: String) {
        pinned.removeAll { $0.key == key }
    }

    public mutating func reorderPins(by order: [String]) {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        pinned = pinned.enumerated()
            .sorted { (rank[$0.element.key] ?? Int.max, $0.offset) < (rank[$1.element.key] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    public mutating func movePin(key: String, to index: Int) {
        guard let from = pinned.firstIndex(where: { $0.key == key }) else { return }
        let item = pinned.remove(at: from)
        pinned.insert(item, at: min(max(index, 0), pinned.count))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
