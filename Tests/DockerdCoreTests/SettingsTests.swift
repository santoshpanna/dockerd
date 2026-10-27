import Foundation
import Testing
@testable import DockerdCore

@MainActor
@Suite("Settings persistence")
struct SettingsTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockerd-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    @Test func defaultsWhenNoFileExists() {
        let store = SettingsStore(fileURL: temporaryURL())
        #expect(store.settings == Settings())
        #expect(store.settings.grouping.defaultMode == .grouped)
        #expect(store.settings.dockVisible)
    }

    @Test func rulesPersistAcrossLaunches() throws {
        let url = temporaryURL()
        let store = SettingsStore(fileURL: url)
        store.update {
            $0.grouping.setMode(.ungrouped, for: Fixture.vscode)
            $0.grouping.setMode(.grouped, for: Fixture.safari)
            $0.grouping.setMode(.grouped, for: Fixture.terminal)
        }
        store.flush()
        let reloaded = SettingsStore(fileURL: url)
        #expect(reloaded.settings.grouping.mode(for: Fixture.vscode) == .ungrouped)
        #expect(reloaded.settings.grouping.mode(for: Fixture.safari) == .grouped)
        #expect(reloaded.settings.grouping.rules.count == 3)

        reloaded.update { $0.grouping.setMode(nil, for: Fixture.vscode) }
        reloaded.flush()
        #expect(SettingsStore(fileURL: url).settings.grouping.explicitMode(for: Fixture.vscode) == nil)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func observersSeeChangesImmediately() {
        let store = SettingsStore(fileURL: temporaryURL())
        var seen: [GroupingMode] = []
        store.observe { _, next in seen.append(next.grouping.mode(for: Fixture.vscode)) }
        store.update { $0.grouping.setMode(.ungrouped, for: Fixture.vscode) }
        store.update { $0.grouping.setMode(.ungrouped, for: Fixture.vscode) }
        #expect(seen == [.ungrouped])
    }

    @Test func restoreDefaultsResetsEverything() {
        let store = SettingsStore(fileURL: temporaryURL())
        store.update {
            $0.appearance.iconSize = 80
            $0.grouping.setMode(.ungrouped, for: Fixture.vscode)
            $0.pin(PinnedApp(bundleID: Fixture.safari, path: "/Applications/Safari.app", name: "Safari"))
        }
        store.restoreDefaults()
        #expect(store.settings == Settings())
    }

    @Test func corruptFileFallsBackToDefaultsAndIsBackedUp() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        #expect(store.settings == Settings())
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(contents.contains { $0.contains("corrupt") })
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func partialAndOutOfRangeValuesDecodeSafely() throws {
        let json = """
        {"appearance": {"iconSize": 500, "edge": "diagonal"}, "grouping": {"rules": {"com.microsoft.vscode": "ungrouped", "x": "bogus"}}}
        """
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.appearance.iconSize == AppearanceSettings.iconSizeRange.upperBound)
        #expect(settings.appearance.edge == .bottom)
        #expect(settings.grouping.rules == ["com.microsoft.vscode": .ungrouped])
        #expect(settings.displays == DisplaySettings())
    }

    @Test func pinningOrderAndRemoval() {
        var settings = Settings()
        let a = PinnedApp(bundleID: "a", path: "/A.app", name: "A")
        let b = PinnedApp(bundleID: "b", path: "/B.app", name: "B")
        let c = PinnedApp(bundleID: "c", path: "/C.app", name: "C")
        settings.pin(a)
        settings.pin(b)
        settings.pin(c, at: 0)
        #expect(settings.pinned.map(\.name) == ["C", "A", "B"])
        settings.movePin(key: c.key, to: 2)
        #expect(settings.pinned.map(\.name) == ["A", "B", "C"])
        settings.pin(a, at: 99)
        #expect(settings.pinned.map(\.name) == ["B", "C", "A"])
        settings.unpin(key: b.key)
        #expect(settings.pinned.map(\.name) == ["C", "A"])
        #expect(settings.isPinned(Fixture.app(1, "a")))
    }

    @Test func clampingAppliesOnAssignment() {
        var appearance = AppearanceSettings()
        appearance.iconSize = 4
        appearance.spacing = -3
        #expect(appearance.iconSize == AppearanceSettings.iconSizeRange.lowerBound)
        #expect(appearance.spacing == 0)
    }
}

@Suite("Accessibility permission state")
struct PermissionStateTests {
    @Test func deniedThenGrantedThenRevokedThenRecovered() {
        var machine = PermissionStateMachine()
        #expect(machine.update(trusted: false) == .denied)
        #expect(machine.update(trusted: false) == nil)
        #expect(machine.update(trusted: true) == .granted)
        #expect(machine.update(trusted: true) == nil)
        #expect(machine.update(trusted: false) == .revoked)
        #expect(machine.update(trusted: false) == nil)
        #expect(machine.update(trusted: true) == .granted)
    }

    @Test func grantedAtLaunch() {
        var machine = PermissionStateMachine()
        #expect(machine.update(trusted: true) == .granted)
        #expect(machine.state.isGranted)
    }
}

@MainActor
@Suite("Separators and system Dock settings")
struct SeparatorSettingsTests {
    @Test func reorderPinsFollowsGivenOrder() {
        var settings = Settings()
        let a = PinnedApp(bundleID: "a", path: "/A.app", name: "A")
        let b = PinnedApp(bundleID: "b", path: "/B.app", name: "B")
        let separator = PinnedApp.separator(id: "s")
        settings.pinned = [a, separator, b]
        settings.reorderPins(by: [b.key, "bundle:unpinned", a.key, separator.key])
        #expect(settings.pinned.map(\.name) == ["B", "A", "Separator"])
    }

    @Test func separatorsAndSystemDockStatePersist() throws {
        var settings = Settings()
        settings.pin(.separator(id: "s"))
        settings.appearance.separatorAfterPinned = true
        settings.systemDock.hideWhileRunning = true
        settings.systemDock.hiddenByDockerd = true
        settings.systemDock.savedAutohide = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.pinned[0].isSeparator)
    }

    @Test func olderFilesWithoutNewFieldsStillDecode() throws {
        let json = #"{"pinned": [{"bundleID": "a", "path": "/A.app", "name": "A"}]}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(!settings.pinned[0].isSeparator)
        #expect(settings.systemDock == SystemDockSettings())
        #expect(!settings.appearance.separatorAfterPinned)
    }

    @Test func restoreDefaultsKeepsSavedDockValuesButTurnsHidingOff() {
        let store = SettingsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("dockerd-tests-\(UUID().uuidString)/settings.json"))
        store.update {
            $0.systemDock.hideWhileRunning = true
            $0.systemDock.hiddenByDockerd = true
            $0.systemDock.savedAutohideDelay = 0.2
        }
        store.restoreDefaults()
        #expect(!store.settings.systemDock.hideWhileRunning)
        #expect(store.settings.systemDock.hiddenByDockerd)
        #expect(store.settings.systemDock.savedAutohideDelay == 0.2)
    }

    @Test func restoreDefaultsKeepsLoginItemDecision() {
        let store = SettingsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("dockerd-tests-\(UUID().uuidString)/settings.json"))
        store.update { $0.loginItemConfigured = true }
        store.restoreDefaults()
        #expect(store.settings.loginItemConfigured)
    }

    @Test func loginItemFlagDefaultsOffForOlderFiles() throws {
        let data = Data(#"{"schemaVersion":1}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(!decoded.loginItemConfigured)
    }
}
