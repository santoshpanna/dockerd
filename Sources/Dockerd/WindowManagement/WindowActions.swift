import AppKit
import ApplicationServices
import DockerdCore
import os

final class WindowActions {
    private let tracker: WindowTracker
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "actions")

    init(tracker: WindowTracker) {
        self.tracker = tracker
    }

    func activate(_ window: WindowInfo) {
        guard let element = tracker.element(for: window.id) else {
            activateApp(pid: window.pid)
            return
        }
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true { app?.unhide() }
        if element.bool(kAXMinimizedAttribute) == true {
            element.set(kAXMinimizedAttribute, false)
        }
        let main = element.set(kAXMainAttribute, true)
        let raise = element.perform(kAXRaiseAction)
        let frontmost = tracker.appElement(window.pid).set(kAXFrontmostAttribute, true)
        logger.notice("activate window pid=\(window.pid, privacy: .public) app=\(window.bundleID ?? "?", privacy: .public) main=\(main.rawValue, privacy: .public) raise=\(raise.rawValue, privacy: .public) frontmost=\(frontmost.rawValue, privacy: .public)")
        if frontmost != .success { activateApp(pid: window.pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let element = self.tracker.element(for: window.id) else { return }
                element.set(kAXMainAttribute, true)
                element.perform(kAXRaiseAction)
                self.tracker.markDirty(window.pid)
            }
        }
        verifyFrontmost(pid: window.pid)
    }

    private func verifyFrontmost(pid: pid_t) {
        let logger = self.logger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == pid {
                logger.notice("activate ok pid=\(pid, privacy: .public)")
            } else {
                logger.error("activate failed pid=\(pid, privacy: .public) frontmost=\(front?.processIdentifier ?? -1, privacy: .public) \(front?.bundleIdentifier ?? "?", privacy: .public)")
            }
        }
    }

    func setFrame(_ window: WindowInfo, to frame: CGRect) -> Bool {
        guard let element = tracker.element(for: window.id) else { return false }
        let size1 = element.set(kAXSizeAttribute, size: frame.size)
        let position = element.set(kAXPositionAttribute, point: frame.origin)
        let size2 = element.set(kAXSizeAttribute, size: frame.size)
        let ok = position == .success && (size1 == .success || size2 == .success)
        logger.notice("clear dock pid=\(window.pid, privacy: .public) app=\(window.bundleID ?? "?", privacy: .public) to=\(String(describing: frame), privacy: .public) ok=\(ok, privacy: .public)")
        tracker.markDirty(window.pid)
        return ok
    }

    func minimize(_ window: WindowInfo) {
        guard let element = tracker.element(for: window.id) else { return }
        element.set(kAXMinimizedAttribute, true)
        tracker.markDirty(window.pid)
    }

    func restore(_ window: WindowInfo) {
        activate(window)
    }

    func close(_ window: WindowInfo) {
        guard let element = tracker.element(for: window.id) else { return }
        if let button = element.element(kAXCloseButtonAttribute) {
            button.perform(kAXPressAction)
        }
        tracker.markDirty(window.pid)
    }

    func activateApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        defer { verifyFrontmost(pid: pid) }
        if tracker.accessibilityEnabled {
            let frontmost = tracker.appElement(pid).set(kAXFrontmostAttribute, true)
            logger.notice("activate app pid=\(pid, privacy: .public) app=\(app.bundleIdentifier ?? "?", privacy: .public) frontmost=\(frontmost.rawValue, privacy: .public)")
            if frontmost == .success { return }
        }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
        }
        app.activate(options: [.activateAllWindows])
    }

    func reopen(item: DockItem) {
        if let path = item.bundlePath {
            launch(path: path)
        } else if let pid = item.pids.first {
            activateApp(pid: pid)
        }
    }

    func launch(path: String) {
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let logger = self.logger
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("Launching \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func hide(pids: [pid_t]) {
        pids.compactMap { NSRunningApplication(processIdentifier: $0) }.forEach { $0.hide() }
    }

    func quit(pids: [pid_t]) {
        pids.compactMap { NSRunningApplication(processIdentifier: $0) }.forEach { $0.terminate() }
    }
}
