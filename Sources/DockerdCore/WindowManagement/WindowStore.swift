import CoreGraphics
import Foundation

public struct ObservedWindow<Element: Hashable> {
    public var element: Element
    public var snapshot: WindowSnapshot
    public var cgWindowID: UInt32?
    public var isOnScreen: Bool?

    public init(element: Element, snapshot: WindowSnapshot, cgWindowID: UInt32? = nil, isOnScreen: Bool? = nil) {
        self.element = element
        self.snapshot = snapshot
        self.cgWindowID = cgWindowID
        self.isOnScreen = isOnScreen
    }
}

public struct WindowStore<Element: Hashable> {
    private var nextRawID: UInt64 = 1
    private var windowsByID: [WindowID: WindowInfo] = [:]
    private var elementByID: [WindowID: Element] = [:]
    private var idByElement: [Element: WindowID] = [:]

    public init() {}

    public var windows: [WindowInfo] {
        windowsByID.values.sorted { $0.id < $1.id }
    }

    public var count: Int { windowsByID.count }

    public func windows(pid: pid_t) -> [WindowInfo] {
        windowsByID.values.filter { $0.pid == pid }.sorted { $0.id < $1.id }
    }

    public func window(_ id: WindowID) -> WindowInfo? {
        windowsByID[id]
    }

    public func element(for id: WindowID) -> Element? {
        elementByID[id]
    }

    public func id(for element: Element) -> WindowID? {
        idByElement[element]
    }

    @discardableResult
    public mutating func reconcile(
        app: AppInfo,
        observed: [ObservedWindow<Element>],
        isWindowAlive: (UInt32) -> Bool = { _ in false }
    ) -> Bool {
        let before = windows(pid: app.pid)
        var seen = Set<WindowID>()

        for item in observed {
            var id = idByElement[item.element]
            if id != nil, seen.contains(id!) { continue }
            if id == nil, let cg = item.cgWindowID {
                if let existing = windowsByID.values.first(where: {
                    $0.pid == app.pid && $0.cgWindowID == cg && !seen.contains($0.id)
                }) {
                    if let oldElement = elementByID[existing.id] { idByElement[oldElement] = nil }
                    id = existing.id
                }
            }
            let resolved = id ?? allocateID()
            if let oldElement = elementByID[resolved], oldElement != item.element {
                idByElement[oldElement] = nil
            }
            elementByID[resolved] = item.element
            idByElement[item.element] = resolved
            let previous = windowsByID[resolved]
            windowsByID[resolved] = WindowInfo(
                id: resolved,
                pid: app.pid,
                bundleID: app.bundleID,
                appName: app.name,
                title: item.snapshot.title,
                frame: item.snapshot.frame,
                isMinimized: item.snapshot.isMinimized,
                isFocused: item.snapshot.isFocused,
                presence: Self.presence(snapshot: item.snapshot, app: app, isOnScreen: item.isOnScreen),
                cgWindowID: item.cgWindowID ?? previous?.cgWindowID
            )
            seen.insert(resolved)
        }

        for stale in before where !seen.contains(stale.id) {
            if let cg = stale.cgWindowID, isWindowAlive(cg) {
                var retained = stale
                retained.appName = app.name
                retained.bundleID = app.bundleID
                retained.isFocused = false
                retained.presence = stale.isMinimized ? .minimized : (app.isHidden ? .hidden : .otherSpace)
                windowsByID[stale.id] = retained
            } else {
                drop(stale.id)
            }
        }

        return before != windows(pid: app.pid)
    }

    @discardableResult
    public mutating func removeWindow(element: Element) -> Bool {
        guard let id = idByElement[element] else { return false }
        drop(id)
        return true
    }

    @discardableResult
    public mutating func removeApp(pid: pid_t) -> Bool {
        let ids = windowsByID.values.filter { $0.pid == pid }.map(\.id)
        ids.forEach { drop($0) }
        return !ids.isEmpty
    }

    @discardableResult
    public mutating func retainApps(_ pids: Set<pid_t>) -> Bool {
        let stale = Set(windowsByID.values.map(\.pid)).subtracting(pids)
        var changed = false
        for pid in stale where removeApp(pid: pid) {
            changed = true
        }
        return changed
    }

    public mutating func removeAll() {
        windowsByID.removeAll()
        elementByID.removeAll()
        idByElement.removeAll()
    }

    static func presence(snapshot: WindowSnapshot, app: AppInfo, isOnScreen: Bool?) -> WindowPresence {
        if snapshot.isMinimized { return .minimized }
        if app.isHidden { return .hidden }
        if isOnScreen == false { return .otherSpace }
        return .onScreen
    }

    private mutating func allocateID() -> WindowID {
        defer { nextRawID += 1 }
        return WindowID(nextRawID)
    }

    private mutating func drop(_ id: WindowID) {
        windowsByID[id] = nil
        if let element = elementByID.removeValue(forKey: id) {
            idByElement[element] = nil
        }
    }
}
