import AppKit
import DockerdCore
import os

final class SystemDockController {
    private static let domain = "com.apple.dock" as CFString
    private static let autohideKey = "autohide"
    private static let delayKey = "autohide-delay"
    private static let hiddenDelay: Float = 1000

    private let store: SettingsStore
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "system-dock")

    init(store: SettingsStore) {
        self.store = store
    }

    func start() {
        store.observe { [weak self] previous, next in
            guard previous.systemDock.hideWhileRunning != next.systemDock.hideWhileRunning else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.sync() }
            }
        }
        sync()
    }

    func restoreBeforeQuit() {
        if store.settings.systemDock.hiddenByDockerd { restore() }
    }

    private func sync() {
        let state = store.settings.systemDock
        if state.hideWhileRunning && !state.hiddenByDockerd {
            hide()
        } else if !state.hideWhileRunning && state.hiddenByDockerd {
            restore()
        }
    }

    private func hide() {
        let autohide = CFPreferencesCopyAppValue(Self.autohideKey as CFString, Self.domain) as? Bool
        let delay = (CFPreferencesCopyAppValue(Self.delayKey as CFString, Self.domain) as? NSNumber)?.doubleValue
        store.update {
            $0.systemDock.savedAutohide = autohide
            $0.systemDock.savedAutohideDelay = delay
            $0.systemDock.hiddenByDockerd = true
        }
        store.flush()
        write([
            Self.autohideKey: kCFBooleanTrue,
            Self.delayKey: NSNumber(value: Self.hiddenDelay),
        ])
        restartDock()
        logger.info("System Dock hidden")
    }

    private func restore() {
        let state = store.settings.systemDock
        write([
            Self.autohideKey: state.savedAutohide.map { NSNumber(value: $0) },
            Self.delayKey: state.savedAutohideDelay.map { NSNumber(value: Float($0)) },
        ])
        store.update {
            $0.systemDock.hiddenByDockerd = false
            $0.systemDock.savedAutohide = nil
            $0.systemDock.savedAutohideDelay = nil
        }
        store.flush()
        restartDock()
        logger.info("System Dock restored")
    }

    private func write(_ values: [String: CFPropertyList?]) {
        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value ?? nil, Self.domain)
        }
        if !CFPreferencesAppSynchronize(Self.domain) {
            logger.error("Could not save Dock preferences")
        }
    }

    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.error("killall Dock exited with \(process.terminationStatus, privacy: .public)")
            }
        } catch {
            logger.error("Could not restart the Dock: \(error.localizedDescription, privacy: .public)")
        }
    }
}
