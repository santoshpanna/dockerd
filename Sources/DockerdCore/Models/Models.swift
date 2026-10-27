import CoreGraphics
import Foundation

public struct WindowID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: WindowID, rhs: WindowID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "w\(rawValue)" }
}

public enum WindowPresence: String, Sendable, Equatable {
    case onScreen
    case minimized
    case hidden
    case otherSpace
}

public struct WindowSnapshot: Equatable, Sendable {
    public var title: String
    public var frame: CGRect?
    public var isMinimized: Bool
    public var isFocused: Bool

    public init(title: String, frame: CGRect?, isMinimized: Bool, isFocused: Bool) {
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFocused = isFocused
    }
}

public struct WindowInfo: Identifiable, Equatable, Sendable {
    public let id: WindowID
    public var pid: pid_t
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var frame: CGRect?
    public var isMinimized: Bool
    public var isFocused: Bool
    public var presence: WindowPresence
    public var cgWindowID: UInt32?

    public init(
        id: WindowID,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        title: String,
        frame: CGRect?,
        isMinimized: Bool,
        isFocused: Bool,
        presence: WindowPresence,
        cgWindowID: UInt32? = nil
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFocused = isFocused
        self.presence = presence
        self.cgWindowID = cgWindowID
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}

public enum AppKey {
    public static func make(bundleID: String?, bundlePath: String?, pid: pid_t?) -> String {
        if let bundleID, !bundleID.isEmpty { return "bundle:" + bundleID.lowercased() }
        if let bundlePath, !bundlePath.isEmpty { return "path:" + bundlePath }
        return "pid:\(pid ?? 0)"
    }
}

public struct AppInfo: Identifiable, Equatable, Sendable {
    public var pid: pid_t
    public var bundleID: String?
    public var name: String
    public var bundlePath: String?
    public var isHidden: Bool
    public var isActive: Bool
    public var launchSequence: UInt64

    public init(
        pid: pid_t,
        bundleID: String?,
        name: String,
        bundlePath: String? = nil,
        isHidden: Bool = false,
        isActive: Bool = false,
        launchSequence: UInt64 = 0
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.bundlePath = bundlePath
        self.isHidden = isHidden
        self.isActive = isActive
        self.launchSequence = launchSequence
    }

    public var id: pid_t { pid }
    public var key: String { AppKey.make(bundleID: bundleID, bundlePath: bundlePath, pid: pid) }
}

public struct PinnedApp: Codable, Hashable, Sendable {
    public var bundleID: String?
    public var path: String
    public var name: String
    public var separatorID: String?

    public init(bundleID: String?, path: String, name: String) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
    }

    public static func separator(id: String = UUID().uuidString) -> PinnedApp {
        var pin = PinnedApp(bundleID: nil, path: "", name: "Separator")
        pin.separatorID = id
        return pin
    }

    public var isSeparator: Bool { separatorID != nil }

    public var key: String {
        if let separatorID { return "sep:\(separatorID)" }
        return AppKey.make(bundleID: bundleID, bundlePath: path, pid: nil)
    }

    public func matches(_ app: AppInfo) -> Bool {
        if isSeparator { return false }
        if let bundleID, let other = app.bundleID {
            return bundleID.caseInsensitiveCompare(other) == .orderedSame
        }
        return app.bundlePath == path
    }
}

public struct DockItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case launcher
        case application
        case window
        case accessibilityNotice
        case separator
        case downloads
        case trash
    }

    public var id: String
    public var kind: Kind
    public var appKey: String
    public var bundleID: String?
    public var bundlePath: String?
    public var appName: String
    public var pids: [pid_t]
    public var windows: [WindowInfo]
    public var isPinned: Bool
    public var isActive: Bool
    public var isHidden: Bool
    public var badge: String?
    public var isLaunching = false

    public init(
        id: String,
        kind: Kind,
        appKey: String,
        bundleID: String?,
        bundlePath: String?,
        appName: String,
        pids: [pid_t],
        windows: [WindowInfo],
        isPinned: Bool,
        isActive: Bool,
        isHidden: Bool
    ) {
        self.id = id
        self.kind = kind
        self.appKey = appKey
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.appName = appName
        self.pids = pids
        self.windows = windows
        self.isPinned = isPinned
        self.isActive = isActive
        self.isHidden = isHidden
    }

    public var isRunning: Bool { !pids.isEmpty }
    public var window: WindowInfo? { kind == .window ? windows.first : nil }
    public var title: String { window?.displayTitle ?? appName }
    public var isFocusedWindow: Bool { kind == .window && isActive && (window?.isFocused ?? false) }
}
