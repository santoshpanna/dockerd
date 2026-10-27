import Foundation

public struct DockBadge: Equatable, Sendable {
    public var path: String?
    public var name: String
    public var label: String

    public init(path: String?, name: String, label: String) {
        self.path = path
        self.name = name
        self.label = label
    }
}

public enum DockDecorations {
    public static func apply(
        to items: [DockItem],
        badges: [DockBadge],
        launching: Set<String>,
        normalize: (String) -> String = { $0 }
    ) -> [DockItem] {
        var byPath: [String: String] = [:]
        var byName: [String: String] = [:]
        for badge in badges where !badge.label.isEmpty {
            if let path = badge.path { byPath[normalize(path)] = badge.label }
            byName[badge.name] = badge.label
        }
        let normalizedLaunching = Set(launching.map(normalize))
        return items.map { item in
            var next = item
            switch item.kind {
            case .application, .window, .launcher:
                let path = item.bundlePath.map(normalize)
                next.badge = path.flatMap { byPath[$0] } ?? byName[item.appName]
                next.isLaunching = item.kind == .launcher && path.map(normalizedLaunching.contains) == true
            case .accessibilityNotice, .separator, .downloads, .trash:
                break
            }
            return next
        }
    }
}

public struct LaunchTracker: Sendable {
    public static let timeout: TimeInterval = 30
    private var pending: [String: Date] = [:]

    public init() {}

    public var paths: Set<String> { Set(pending.keys) }

    public mutating func begin(_ path: String, at now: Date) {
        pending[path] = now
    }

    @discardableResult
    public mutating func settle(runningPaths: Set<String>, now: Date) -> Bool {
        let before = pending.count
        pending = pending.filter { path, started in
            !runningPaths.contains(path) && now.timeIntervalSince(started) < Self.timeout
        }
        return pending.count != before
    }
}
