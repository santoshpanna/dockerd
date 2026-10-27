import AppKit
import ApplicationServices
import DockerdCore

final class PermissionController {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private var machine = PermissionStateMachine()
    private var timer: Timer?
    private var observers: [(AccessibilityPermission) -> Void] = []

    var state: AccessibilityPermission { machine.state }

    func observe(_ observer: @escaping (AccessibilityPermission) -> Void) {
        observers.append(observer)
    }

    func start() {
        check()
        schedule()
    }

    func check() {
        if let next = machine.update(trusted: AXIsProcessTrusted()) {
            observers.forEach { $0(next) }
            schedule()
        }
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        check()
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    func reportAPIDisabled() {
        if let next = machine.update(trusted: false) {
            observers.forEach { $0(next) }
            schedule()
        }
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = machine.state.isGranted ? 5 : 1.5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = interval / 4
    }
}
