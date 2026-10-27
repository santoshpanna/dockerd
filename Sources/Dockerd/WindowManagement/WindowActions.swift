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
        element.set(kAXMainAttribute, true)
        element.perform(kAXRaiseAction)
        let frontmost = tracker.appElement(window.pid).set(kAXFrontmostAttribute, true)
        if frontmost != .success { activateApp(pid: window.pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let element = self.tracker.element(for: window.id) else { return }
                element.set(kAXMainAttribute, true)
                element.perform(kAXRaiseAction)
                self.tracker.markDirty(window.pid)
            }
        }
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
        if tracker.accessibilityEnabled, tracker.appElement(pid).set(kAXFrontmostAttribute, true) == .success {
            return
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
