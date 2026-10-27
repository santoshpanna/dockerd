import Foundation

public struct TaskbarInput: Sendable {
    public var apps: [AppInfo]
    public var windows: [WindowInfo]
    public var pins: [PinnedApp]
    public var policy: GroupingPolicy
    public var dockDisplays: [DisplayInfo]
    public var targetDisplayID: UInt32?
    public var placement: WindowPlacement
    public var currentSpaceOnly: Bool
    public var accessibilityGranted: Bool
    public var preferredOrder: [String]
    public var preferredWindowOrder: [WindowID]
    public var separatorAfterPinned: Bool
    public var showDownloads: Bool
    public var showTrash: Bool

    public init(
        apps: [AppInfo],
        windows: [WindowInfo],
        pins: [PinnedApp],
        policy: GroupingPolicy,
        dockDisplays: [DisplayInfo] = [],
        targetDisplayID: UInt32? = nil,
        placement: WindowPlacement = .ownDisplay,
        currentSpaceOnly: Bool = false,
        accessibilityGranted: Bool = true,
        preferredOrder: [String] = [],
        preferredWindowOrder: [WindowID] = [],
        separatorAfterPinned: Bool = false,
        showDownloads: Bool = false,
        showTrash: Bool = false
    ) {
        self.apps = apps
        self.windows = windows
        self.pins = pins
        self.policy = policy
        self.dockDisplays = dockDisplays
        self.targetDisplayID = targetDisplayID
        self.placement = placement
        self.currentSpaceOnly = currentSpaceOnly
        self.accessibilityGranted = accessibilityGranted
        self.preferredOrder = preferredOrder
        self.preferredWindowOrder = preferredWindowOrder
        self.separatorAfterPinned = separatorAfterPinned
        self.showDownloads = showDownloads
        self.showTrash = showTrash
    }
}

public enum TaskbarOrder {
    public static func merge<Key: Hashable>(base: [Key], preferred: [Key]) -> [Key] {
        let present = Set(base)
        var result: [Key] = []
        var placed = Set<Key>()
        for key in preferred where present.contains(key) && !placed.contains(key) {
            result.append(key)
            placed.insert(key)
        }
        var placedAfter = [Bool](repeating: false, count: base.count)
        var seen = false
        for index in base.indices.reversed() {
            placedAfter[index] = seen
            if placed.contains(base[index]) { seen = true }
        }
        var anchor: Key?
        for (position, key) in base.enumerated() {
            if placed.contains(key) {
                anchor = key
                continue
            }
            let index: Int
            if !placedAfter[position] {
                index = result.count
            } else {
                index = anchor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            }
            result.insert(key, at: index)
            placed.insert(key)
            anchor = key
        }
        return result
    }

    public static func move<Key: Hashable>(_ key: Key, in order: [Key], before anchor: Key?, orAfter fallback: Key?) -> [Key] {
        var result = order.filter { $0 != key }
        if let anchor, let index = result.firstIndex(of: anchor) {
            result.insert(key, at: index)
        } else if let fallback, let index = result.firstIndex(of: fallback) {
            result.insert(key, at: index + 1)
        } else {
            result.append(key)
        }
        return result
    }
}

public enum TaskbarLayoutBuilder {
    public static let autoSeparatorID = "sep:auto"
    public static let systemSeparatorID = "sep:system"
    public static let downloadsID = "sys:downloads"
    public static let trashID = "sys:trash"

    struct Plan {
        var keys: [String]
        var pinByKey: [String: PinnedApp]
        var groups: [String: [AppInfo]]
    }

    public static func keyOrder(_ input: TaskbarInput) -> [String] {
        plan(input).keys
    }

    public static func windowOrder(_ input: TaskbarInput) -> [WindowID] {
        TaskbarOrder.merge(base: input.windows.map(\.id).sorted(), preferred: input.preferredWindowOrder)
    }

    static func plan(_ input: TaskbarInput) -> Plan {
        var groups: [String: [AppInfo]] = [:]
        var runningOrder: [String] = []
        for app in input.apps.sorted(by: { ($0.launchSequence, $0.pid) < ($1.launchSequence, $1.pid) }) {
            let key = app.key
            if groups[key] == nil { runningOrder.append(key) }
            groups[key, default: []].append(app)
        }

        var orderedKeys: [String] = []
        var pinByKey: [String: PinnedApp] = [:]
        for pin in input.pins {
            let running = groups.first { _, apps in apps.contains(where: pin.matches) }?.key
            let key = running ?? pin.key
            guard pinByKey[key] == nil else { continue }
            pinByKey[key] = pin
            orderedKeys.append(key)
        }
        orderedKeys.append(contentsOf: runningOrder.filter { pinByKey[$0] == nil })
        let keys = TaskbarOrder.merge(base: orderedKeys, preferred: input.preferredOrder)
        return Plan(keys: keys, pinByKey: pinByKey, groups: groups)
    }

    public static func build(_ input: TaskbarInput) -> [DockItem] {
        let eligible = input.windows.filter { !(input.currentSpaceOnly && $0.presence == .otherSpace) }
        let local = eligible.filter { isShown($0, input: input) }
        let localByPID = Dictionary(grouping: local, by: \.pid)
        let allByPID = Dictionary(grouping: eligible, by: \.pid)
        let plan = plan(input)
        let pinByKey = plan.pinByKey
        let groups = plan.groups
        let windowRank = Dictionary(windowOrder(input).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        var items: [DockItem] = []
        for key in plan.keys {
            let pin = pinByKey[key]
            if let pin, pin.isSeparator {
                items.append(separator(id: pin.key, isPinned: true))
                continue
            }
            guard let apps = groups[key], let primary = apps.first else {
                if let pin { items.append(launcher(pin)) }
                continue
            }
            let pids = apps.map(\.pid)
            let windows = pids.flatMap { localByPID[$0] ?? [] }.sorted { (windowRank[$0.id] ?? Int.max, $0.id) < (windowRank[$1.id] ?? Int.max, $1.id) }
            let hasWindowsElsewhere = pids.contains { !(allByPID[$0] ?? []).isEmpty }
            let isActive = apps.contains(where: \.isActive)
            let isHidden = apps.allSatisfy(\.isHidden)
            let mode = input.policy.mode(for: primary.bundleID)

            if windows.isEmpty && hasWindowsElsewhere && pin == nil { continue }

            if mode == .ungrouped && !windows.isEmpty {
                for window in windows {
                    items.append(DockItem(
                        id: "win:\(window.id.rawValue)",
                        kind: .window,
                        appKey: key,
                        bundleID: primary.bundleID,
                        bundlePath: primary.bundlePath ?? pin?.path,
                        appName: primary.name,
                        pids: pids,
                        windows: [window],
                        isPinned: pin != nil,
                        isActive: isActive,
                        isHidden: isHidden))
                }
            } else {
                items.append(DockItem(
                    id: "app:\(key)",
                    kind: .application,
                    appKey: key,
                    bundleID: primary.bundleID,
                    bundlePath: primary.bundlePath ?? pin?.path,
                    appName: primary.name,
                    pids: pids,
                    windows: windows,
                    isPinned: pin != nil,
                    isActive: isActive,
                    isHidden: isHidden))
            }
        }
        if input.separatorAfterPinned, let last = items.lastIndex(where: { $0.isPinned }), last < items.count - 1,
           items[last].kind != .separator, items[last + 1].kind != .separator {
            items.insert(separator(id: autoSeparatorID, isPinned: false), at: last + 1)
        }
        var trailing: [DockItem] = []
        if input.showDownloads { trailing.append(systemItem(id: downloadsID, kind: .downloads, name: "Downloads")) }
        if input.showTrash { trailing.append(systemItem(id: trashID, kind: .trash, name: "Trash")) }
        if !trailing.isEmpty {
            if !items.isEmpty && items.last?.kind != .separator {
                items.append(separator(id: systemSeparatorID, isPinned: false))
            }
            items.append(contentsOf: trailing)
        }
        if !input.accessibilityGranted { items.insert(accessibilityNotice, at: 0) }
        return items
    }

    public static func isFixed(_ item: DockItem) -> Bool {
        switch item.kind {
        case .accessibilityNotice, .downloads, .trash: return true
        case .separator: return !item.isPinned
        case .launcher, .application, .window: return false
        }
    }

    static func systemItem(id: String, kind: DockItem.Kind, name: String) -> DockItem {
        DockItem(
            id: id,
            kind: kind,
            appKey: id,
            bundleID: nil,
            bundlePath: nil,
            appName: name,
            pids: [],
            windows: [],
            isPinned: false,
            isActive: false,
            isHidden: false)
    }

    static func separator(id: String, isPinned: Bool) -> DockItem {
        DockItem(
            id: id,
            kind: .separator,
            appKey: id,
            bundleID: nil,
            bundlePath: nil,
            appName: "Separator",
            pids: [],
            windows: [],
            isPinned: isPinned,
            isActive: false,
            isHidden: false)
    }

    public static let accessibilityNoticeID = "notice:accessibility"

    static let accessibilityNotice = DockItem(
        id: accessibilityNoticeID,
        kind: .accessibilityNotice,
        appKey: accessibilityNoticeID,
        bundleID: nil,
        bundlePath: nil,
        appName: "Accessibility Access Needed",
        pids: [],
        windows: [],
        isPinned: false,
        isActive: false,
        isHidden: false)

    static func launcher(_ pin: PinnedApp) -> DockItem {
        DockItem(
            id: "app:\(pin.key)",
            kind: .launcher,
            appKey: pin.key,
            bundleID: pin.bundleID,
            bundlePath: pin.path,
            appName: pin.name,
            pids: [],
            windows: [],
            isPinned: true,
            isActive: false,
            isHidden: false)
    }

    static func isShown(_ window: WindowInfo, input: TaskbarInput) -> Bool {
        guard input.placement == .ownDisplay, let target = input.targetDisplayID, input.dockDisplays.count > 1 else {
            return true
        }
        return WindowDisplayAssigner.display(for: window.frame, among: input.dockDisplays)?.id == target
    }
}
