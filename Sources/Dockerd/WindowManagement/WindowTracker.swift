import AppKit
import ApplicationServices
import DockerdCore
import os

private nonisolated func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let name = notification as String
    nonisolated(unsafe) let pointer = refcon
    nonisolated(unsafe) let target = element
    MainActor.assumeIsolated {
        let box = Unmanaged<AppObserver>.fromOpaque(pointer).takeUnretainedValue()
        box.handle(element: target, notification: name)
    }
}

final class AppObserver {
    static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    let pid: pid_t
    let appElement: AXUIElement
    private var observer: AXObserver?
    private var watchedWindows = Set<AXUIElement>()
    private(set) var isAttached = false
    weak var tracker: WindowTracker?

    init(pid: pid_t, appElement: AXUIElement, tracker: WindowTracker) {
        self.pid = pid
        self.appElement = appElement
        self.tracker = tracker
    }

    func attach() -> AXError {
        if isAttached { return .success }
        var created: AXObserver?
        let error = AXObserverCreate(pid, axObserverCallback, &created)
        guard error == .success, let created else { return error }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var lastError = AXError.success
        var anySucceeded = false
        for name in Self.appNotifications {
            let result = AXObserverAddNotification(created, appElement, name as CFString, refcon)
            if result == .success || result == .notificationAlreadyRegistered {
                anySucceeded = true
            } else {
                lastError = result
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        isAttached = anySucceeded
        return anySucceeded ? .success : lastError
    }

    func watch(window: AXUIElement) {
        guard let observer, !watchedWindows.contains(window) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
        watchedWindows.insert(window)
    }

    func forget(window: AXUIElement) {
        guard watchedWindows.remove(window) != nil, let observer else { return }
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, window, name as CFString)
        }
    }

    func invalidate() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        watchedWindows.removeAll()
        isAttached = false
    }

    func handle(element: AXUIElement, notification: String) {
        guard let tracker else { return }
        if notification == kAXUIElementDestroyedNotification {
            watchedWindows.remove(element)
            tracker.windowDestroyed(element: element, pid: pid)
        } else {
            tracker.markDirty(pid)
        }
    }
}

final class WindowTracker {
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "tracker")
    private(set) var apps: [pid_t: AppInfo] = [:]
    private var store = WindowStore<AXUIElement>()
    private var observers: [pid_t: AppObserver] = [:]
    private var launchSequence: [pid_t: UInt64] = [:]
    private var nextSequence: UInt64 = 1
    private var dirty = Set<pid_t>()
    private var flushScheduled = false
    private var changeScheduled = false
    private var sweepTimer: Timer?
    private var workspaceTokens: [NSObjectProtocol] = []
    private(set) var accessibilityEnabled = false

    var onChange: (() -> Void)?
    var onAccessibilityLost: (() -> Void)?

    static let sweepInterval: TimeInterval = 8
    static let flushDelay: TimeInterval = 0.08
    static let messagingTimeout: Float = 0.3

    var windows: [WindowInfo] { store.windows }
    var appList: [AppInfo] { Array(apps.values) }

    func start(accessibility: Bool) {
        accessibilityEnabled = accessibility
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let isSpaceChange = note.name == NSWorkspace.activeSpaceDidChangeNotification
                MainActor.assumeIsolated {
                    self?.workspaceEvent(pid: pid, spaceChanged: isSpaceChange)
                }
            }
            workspaceTokens.append(token)
        }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
        sweepTimer = Timer.scheduledTimer(withTimeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        sweepTimer?.tolerance = 2
        sweep()
    }

    func stop() {
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        sweepTimer?.invalidate()
        sweepTimer = nil
        observers.values.forEach { $0.invalidate() }
        observers.removeAll()
    }

    func setAccessibility(enabled: Bool) {
        guard enabled != accessibilityEnabled else { return }
        accessibilityEnabled = enabled
        observers.values.forEach { $0.invalidate() }
        observers.removeAll()
        store.removeAll()
        sweep()
        notifyChange()
    }

    func element(for id: WindowID) -> AXUIElement? {
        store.element(for: id)
    }

    func window(_ id: WindowID) -> WindowInfo? {
        store.window(id)
    }

    func appElement(_ pid: pid_t) -> AXUIElement {
        if let observer = observers[pid] { return observer.appElement }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    func markDirty(_ pid: pid_t) {
        dirty.insert(pid)
        scheduleFlush()
    }

    func markAllDirty() {
        dirty.formUnion(apps.keys)
        scheduleFlush()
    }

    func windowDestroyed(element: AXUIElement, pid: pid_t) {
        if store.removeWindow(element: element) { notifyChange() }
        markDirty(pid)
    }

    private func workspaceEvent(pid: pid_t?, spaceChanged: Bool) {
        syncApps()
        if spaceChanged {
            markAllDirty()
        } else if let pid {
            markDirty(pid)
        }
    }

    private func sweep() {
        syncApps()
        markAllDirty()
    }

    private func syncApps() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me
        }
        var next: [pid_t: AppInfo] = [:]
        let fresh = running.filter { launchSequence[$0.processIdentifier] == nil }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        for app in fresh {
            launchSequence[app.processIdentifier] = nextSequence
            nextSequence += 1
        }
        for app in running {
            let pid = app.processIdentifier
            next[pid] = AppInfo(
                pid: pid,
                bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "App",
                bundlePath: app.bundleURL?.path,
                isHidden: app.isHidden,
                isActive: pid == frontmost,
                launchSequence: launchSequence[pid] ?? 0)
        }

        let removed = Set(apps.keys).subtracting(next.keys)
        for pid in removed {
            observers.removeValue(forKey: pid)?.invalidate()
            launchSequence[pid] = nil
            dirty.remove(pid)
        }
        let storeChanged = store.retainApps(Set(next.keys))
        let appsChanged = next != apps
        apps = next

        if accessibilityEnabled {
            for pid in next.keys where observers[pid]?.isAttached != true {
                attachObserver(pid)
            }
        }
        if appsChanged || storeChanged { notifyChange() }
    }

    private func attachObserver(_ pid: pid_t) {
        let observer = observers[pid] ?? {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            let created = AppObserver(pid: pid, appElement: element, tracker: self)
            observers[pid] = created
            return created
        }()
        let result = observer.attach()
        if result == .apiDisabled { accessibilityFailed() }
        if result == .success { dirty.insert(pid) }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushDelay) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        let pids = dirty
        dirty.removeAll()
        guard accessibilityEnabled, !pids.isEmpty else { return }
        let cg = CGWindowSnapshot.capture()
        var changed = false
        for pid in pids {
            guard let app = apps[pid] else { continue }
            if refresh(app: app, cg: cg) { changed = true }
            if !accessibilityEnabled { return }
        }
        if changed { notifyChange() }
    }

    private func refresh(app: AppInfo, cg: CGWindowSnapshot) -> Bool {
        let appElement = appElement(app.pid)
        let (error, value) = appElement.copyValue(kAXWindowsAttribute)
        let elements: [AXUIElement]
        switch error {
        case .success:
            elements = (value as? [AXUIElement]) ?? []
        case .noValue, .attributeUnsupported:
            elements = []
        case .apiDisabled:
            accessibilityFailed()
            return false
        default:
            return false
        }

        let focused = appElement.element(kAXFocusedWindowAttribute)
        var snapshots: [(AXUIElement, WindowSnapshot)] = []
        for element in elements where AXWindowFilter.isUserWindow(element) {
            let frame = element.frame
            if let frame, frame.width < 20 || frame.height < 20 { continue }
            let snapshot = WindowSnapshot(
                title: element.string(kAXTitleAttribute) ?? "",
                frame: frame,
                isMinimized: element.bool(kAXMinimizedAttribute) ?? false,
                isFocused: focused.map { CFEqual($0, element) } ?? false)
            snapshots.append((element, snapshot))
        }

        var frames: [Int: CGRect] = [:]
        var hints: [Int: UInt32] = [:]
        for (index, entry) in snapshots.enumerated() {
            if let frame = entry.1.frame, !entry.1.isMinimized { frames[index] = frame }
            if let id = store.id(for: entry.0), let cgID = store.window(id)?.cgWindowID { hints[index] = cgID }
        }
        let candidates = cg.byPID[app.pid] ?? []
        let matches = CGWindowMatcher.match(frames: frames, candidates: candidates, hints: hints)
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let observed: [ObservedWindow<AXUIElement>] = snapshots.enumerated().map { index, entry in
            let matched = matches[index] ?? hints[index].flatMap { byID[$0] }
            return ObservedWindow(
                element: entry.0,
                snapshot: entry.1,
                cgWindowID: matched?.id,
                isOnScreen: matched?.isOnScreen)
        }
        let changed = store.reconcile(app: app, observed: observed) { cg.aliveIDs.contains($0) }

        if let observer = observers[app.pid] {
            for entry in snapshots { observer.watch(window: entry.0) }
        }
        return changed
    }

    private func accessibilityFailed() {
        guard accessibilityEnabled else { return }
        logger.error("Accessibility API disabled; window tracking paused")
        onAccessibilityLost?()
    }

    private func notifyChange() {
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changeScheduled = false
                self.onChange?()
            }
        }
    }
}
