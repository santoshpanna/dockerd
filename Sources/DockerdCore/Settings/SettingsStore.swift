import Foundation
import os

@MainActor
public final class SettingsStore {
    public typealias Observer = (Settings, Settings) -> Void

    public let fileURL: URL
    public private(set) var settings: Settings
    public private(set) var lastError: Error?

    private var observers: [UUID: Observer] = [:]
    private var pendingSave: DispatchWorkItem?
    private let saveDelay: TimeInterval
    private let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "settings")

    public init(fileURL: URL, saveDelay: TimeInterval = 0.3) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
        self.settings = Settings()
        self.settings = load()
    }

    public static func defaultFileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Dockerd", isDirectory: true).appendingPathComponent("settings.json")
    }

    @discardableResult
    public func observe(_ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    public func update(_ mutate: (inout Settings) -> Void) {
        var next = settings
        mutate(&next)
        replace(with: next)
    }

    public func restoreDefaults() {
        var fresh = Settings()
        fresh.systemDock = settings.systemDock
        fresh.systemDock.hideWhileRunning = false
        fresh.loginItemConfigured = settings.loginItemConfigured
        replace(with: fresh)
    }

    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    private func replace(with next: Settings) {
        guard next != settings else { return }
        let previous = settings
        settings = next
        scheduleSave()
        for observer in observers.values {
            observer(previous, next)
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.write() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error
            logger.error("Saving settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() -> Settings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Settings() }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            lastError = error
            logger.error("Settings unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
            } catch {
                logger.error("Could not back up unreadable settings: \(error.localizedDescription, privacy: .public)")
            }
            return Settings()
        }
    }
}
