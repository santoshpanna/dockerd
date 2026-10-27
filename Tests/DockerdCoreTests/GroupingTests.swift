import Testing
@testable import DockerdCore

@Suite("Grouping policy")
struct GroupingPolicyTests {
    @Test func defaultsToGroupedWhenNoRuleExists() {
        let policy = GroupingPolicy()
        #expect(policy.mode(for: "com.example.unknown") == .grouped)
        #expect(policy.mode(for: nil) == .grouped)
        #expect(policy.explicitMode(for: "com.example.unknown") == nil)
    }

    @Test func globalDefaultAppliesToUnconfiguredApps() {
        var policy = GroupingPolicy()
        policy.defaultMode = .ungrouped
        policy.setMode(.grouped, for: Fixture.safari)
        #expect(policy.mode(for: "com.example.other") == .ungrouped)
        #expect(policy.mode(for: Fixture.safari) == .grouped)
    }

    @Test func addUpdateAndDeleteRules() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        #expect(policy.mode(for: Fixture.vscode) == .ungrouped)
        policy.setMode(.grouped, for: Fixture.vscode)
        #expect(policy.mode(for: Fixture.vscode) == .grouped)
        #expect(policy.explicitMode(for: Fixture.vscode) == .grouped)
        policy.setMode(nil, for: Fixture.vscode)
        #expect(policy.explicitMode(for: Fixture.vscode) == nil)
        #expect(policy.rules.isEmpty)
    }

    @Test func variantsAreIndependent() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        #expect(policy.mode(for: Fixture.vscode) == .ungrouped)
        #expect(policy.mode(for: Fixture.insiders) == .grouped)
        #expect(policy.mode(for: "com.vscodium") == .grouped)
        #expect(policy.mode(for: "com.todesktop.230313mzl4w4u92") == .grouped)
    }

    @Test func bundleIdentifierMatchingIgnoresCaseAndWhitespace() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: "  com.Microsoft.VSCode ")
        #expect(policy.mode(for: "com.microsoft.vscode") == .ungrouped)
        #expect(policy.sortedRules.map(\.bundleID) == ["com.microsoft.vscode"])
    }

    @Test func emptyBundleIdentifierIsIgnored() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: "   ")
        #expect(policy.rules.isEmpty)
    }
}

@Suite("Taskbar layout")
struct TaskbarLayoutTests {
    func input(
        apps: [AppInfo],
        windows: [WindowInfo],
        pins: [PinnedApp] = [],
        policy: GroupingPolicy = GroupingPolicy()
    ) -> TaskbarInput {
        TaskbarInput(apps: apps, windows: windows, pins: pins, policy: policy)
    }

    @Test func groupedAppProducesOneEntryWithAllWindows() {
        let safari = Fixture.app(10, Fixture.safari)
        let windows = (1...3).map { Fixture.window(UInt64($0), pid: 10, bundleID: Fixture.safari, title: "Tab \($0)") }
        let items = TaskbarLayoutBuilder.build(input(apps: [safari], windows: windows))
        #expect(items.count == 1)
        #expect(items[0].kind == .application)
        #expect(items[0].windows.map(\.title) == ["Tab 1", "Tab 2", "Tab 3"])
    }

    @Test func ungroupedAppProducesOneEntryPerWindow() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let code = Fixture.app(20, Fixture.vscode)
        let windows = ["api", "web", "infra", "docs", "cli"].enumerated().map {
            Fixture.window(UInt64($0.offset + 1), pid: 20, bundleID: Fixture.vscode, title: $0.element)
        }
        let items = TaskbarLayoutBuilder.build(input(apps: [code], windows: windows, policy: policy))
        #expect(items.count == 5)
        #expect(items.allSatisfy { $0.kind == .window })
        #expect(items.map(\.title) == ["api", "web", "infra", "docs", "cli"])
        #expect(Set(items.map(\.id)).count == 5)
    }

    @Test func mixedRulesForVSCodeSafariAndTerminal() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        policy.setMode(.grouped, for: Fixture.safari)
        let apps = [Fixture.app(1, Fixture.vscode), Fixture.app(2, Fixture.safari), Fixture.app(3, Fixture.terminal)]
        let windows = [
            Fixture.window(1, pid: 1, bundleID: Fixture.vscode, title: "repo-a"),
            Fixture.window(2, pid: 1, bundleID: Fixture.vscode, title: "repo-b"),
            Fixture.window(3, pid: 2, bundleID: Fixture.safari, title: "Docs"),
            Fixture.window(4, pid: 2, bundleID: Fixture.safari, title: "Mail"),
            Fixture.window(5, pid: 3, bundleID: Fixture.terminal, title: "zsh"),
            Fixture.window(6, pid: 3, bundleID: Fixture.terminal, title: "ssh"),
        ]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: windows, policy: policy))
        #expect(items.map(\.kind) == [.window, .window, .application, .application])
        #expect(items[2].windows.count == 2)
        #expect(items[3].windows.count == 2)
    }

    @Test func variantsUseTheirOwnRule() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let apps = [Fixture.app(1, Fixture.vscode), Fixture.app(2, Fixture.insiders)]
        let windows = [
            Fixture.window(1, pid: 1, bundleID: Fixture.vscode, title: "a"),
            Fixture.window(2, pid: 1, bundleID: Fixture.vscode, title: "b"),
            Fixture.window(3, pid: 2, bundleID: Fixture.insiders, title: "c"),
            Fixture.window(4, pid: 2, bundleID: Fixture.insiders, title: "d"),
        ]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: windows, policy: policy))
        #expect(items.count == 3)
        #expect(items.last?.bundleID == Fixture.insiders)
        #expect(items.last?.kind == .application)
    }

    @Test func identicalTitlesStayDistinct() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.terminal)
        let apps = [Fixture.app(3, Fixture.terminal)]
        let windows = [
            Fixture.window(7, pid: 3, bundleID: Fixture.terminal, title: "zsh"),
            Fixture.window(8, pid: 3, bundleID: Fixture.terminal, title: "zsh"),
        ]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: windows, policy: policy))
        #expect(items.count == 2)
        #expect(items[0].id != items[1].id)
        #expect(items.map { $0.window?.id } == [WindowID(7), WindowID(8)])
    }

    @Test func ungroupedAppWithoutWindowsStillAppears() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let items = TaskbarLayoutBuilder.build(input(apps: [Fixture.app(1, Fixture.vscode)], windows: [], policy: policy))
        #expect(items.count == 1)
        #expect(items[0].kind == .application)
        #expect(items[0].windows.isEmpty)
    }

    @Test func pinnedAppsComeFirstAndLaunchWhenNotRunning() {
        let pins = [
            PinnedApp(bundleID: Fixture.terminal, path: "/System/Applications/Utilities/Terminal.app", name: "Terminal"),
            PinnedApp(bundleID: Fixture.safari, path: "/Applications/Safari.app", name: "Safari"),
        ]
        let apps = [Fixture.app(5, "com.example.editor"), Fixture.app(6, Fixture.safari)]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: [], pins: pins))
        #expect(items.map(\.appName) == ["Terminal", Fixture.safari, "com.example.editor"])
        #expect(items[0].kind == .launcher)
        #expect(items[0].isPinned)
        #expect(items[1].isRunning && items[1].isPinned)
        #expect(!items[2].isPinned)
    }

    @Test func pinnedEntryKeepsItsIdentityWhenAppLaunches() {
        let pin = PinnedApp(bundleID: Fixture.safari, path: "/Applications/Safari.app", name: "Safari")
        let before = TaskbarLayoutBuilder.build(input(apps: [], windows: [], pins: [pin]))
        let after = TaskbarLayoutBuilder.build(input(apps: [Fixture.app(6, Fixture.safari)], windows: [], pins: [pin]))
        #expect(before.first?.id == after.first?.id)
    }

    @Test func runningOrderFollowsLaunchSequence() {
        let apps = [Fixture.app(9, "b", sequence: 2), Fixture.app(4, "a", sequence: 1), Fixture.app(2, "c", sequence: 3)]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: []))
        #expect(items.map(\.bundleID) == ["a", "b", "c"])
    }

    @Test func activeAndFocusedStateFlowsThrough() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let apps = [Fixture.app(1, Fixture.vscode, active: true)]
        let windows = [
            Fixture.window(1, pid: 1, bundleID: Fixture.vscode, title: "a"),
            Fixture.window(2, pid: 1, bundleID: Fixture.vscode, title: "b", focused: true),
        ]
        let items = TaskbarLayoutBuilder.build(input(apps: apps, windows: windows, policy: policy))
        #expect(items.map(\.isFocusedWindow) == [false, true])
    }

    @Test func minimizedWindowsArePreserved() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let windows = [Fixture.window(1, pid: 1, bundleID: Fixture.vscode, title: "a", presence: .minimized)]
        let items = TaskbarLayoutBuilder.build(input(apps: [Fixture.app(1, Fixture.vscode)], windows: windows, policy: policy))
        #expect(items.count == 1)
        #expect(items[0].window?.presence == .minimized)
    }

    @Test func missingAccessibilityLeadsWithANotice() {
        let code = Fixture.app(20, Fixture.vscode)
        var denied = input(apps: [code], windows: [])
        denied.accessibilityGranted = false
        let items = TaskbarLayoutBuilder.build(denied)
        #expect(items.map(\.kind) == [.accessibilityNotice, .application])
        #expect(items[0].id == TaskbarLayoutBuilder.accessibilityNoticeID)
        #expect(!items[0].isRunning && !items[0].isPinned && items[0].bundlePath == nil)
    }

    @Test func noNoticeWhenAccessibilityIsGranted() {
        let items = TaskbarLayoutBuilder.build(input(apps: [Fixture.app(20, Fixture.vscode)], windows: []))
        #expect(!items.contains { $0.kind == .accessibilityNotice })
    }
}

@Suite("Taskbar order and separators")
struct TaskbarOrderTests {
    @Test func mergeWithoutPreferenceKeepsBase() {
        #expect(TaskbarOrder.merge(base: ["a", "b", "c"], preferred: []) == ["a", "b", "c"])
    }

    @Test func mergeHonoursPreferenceAndPlacesNewKeysAfterTheirPredecessor() {
        let merged = TaskbarOrder.merge(base: ["a", "b", "new", "c", "late"], preferred: ["c", "a", "b", "gone"])
        #expect(merged == ["c", "a", "b", "new", "late"])
    }

    @Test func mergePutsLeadingNewKeysFirst() {
        #expect(TaskbarOrder.merge(base: ["new", "a", "b"], preferred: ["b", "a"]) == ["new", "b", "a"])
    }

    @Test func moveBeforeAnchorOrAfterFallback() {
        #expect(TaskbarOrder.move("c", in: ["a", "b", "c"], before: "a", orAfter: nil) == ["c", "a", "b"])
        #expect(TaskbarOrder.move("a", in: ["a", "b", "c"], before: nil, orAfter: "c") == ["b", "c", "a"])
        #expect(TaskbarOrder.move("x", in: ["a"], before: "missing", orAfter: nil) == ["a", "x"])
    }

    @Test func sessionOrderRearrangesRunningApps() {
        let apps = [Fixture.app(1, Fixture.safari, name: "Safari", sequence: 1), Fixture.app(2, Fixture.terminal, name: "Terminal", sequence: 2)]
        let terminalKey = apps[1].key
        let input = TaskbarInput(apps: apps, windows: [], pins: [], policy: GroupingPolicy(), preferredOrder: [terminalKey, apps[0].key])
        #expect(TaskbarLayoutBuilder.build(input).map(\.appName) == ["Terminal", "Safari"])
        let fresh = TaskbarInput(apps: apps, windows: [], pins: [], policy: GroupingPolicy())
        #expect(TaskbarLayoutBuilder.build(fresh).map(\.appName) == ["Safari", "Terminal"])
    }

    @Test func sessionWindowOrderRearrangesUngroupedWindows() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let code = Fixture.app(20, Fixture.vscode)
        let windows = ["api", "web", "cli"].enumerated().map {
            Fixture.window(UInt64($0.offset + 1), pid: 20, bundleID: Fixture.vscode, title: $0.element)
        }
        let input = TaskbarInput(apps: [code], windows: windows, pins: [], policy: policy, preferredWindowOrder: [WindowID(3), WindowID(1)])
        #expect(TaskbarLayoutBuilder.build(input).map(\.title) == ["cli", "api", "web"])
        let opened = windows + [Fixture.window(4, pid: 20, bundleID: Fixture.vscode, title: "new")]
        let later = TaskbarInput(apps: [code], windows: opened, pins: [], policy: policy, preferredWindowOrder: [WindowID(3), WindowID(1), WindowID(2)])
        #expect(TaskbarLayoutBuilder.build(later).map(\.title) == ["cli", "api", "web", "new"])
    }

    @Test func windowOrderMovesWithinTheFullWindowList() {
        let windows = (1...3).map { Fixture.window(UInt64($0), pid: 20, bundleID: Fixture.vscode, title: "w\($0)") }
        let input = TaskbarInput(apps: [], windows: windows, pins: [], policy: GroupingPolicy(), preferredWindowOrder: [WindowID(9), WindowID(2)])
        let order = TaskbarLayoutBuilder.windowOrder(input)
        #expect(order == [WindowID(1), WindowID(2), WindowID(3)])
        #expect(TaskbarOrder.move(WindowID(3), in: order, before: WindowID(1), orAfter: nil) == [WindowID(3), WindowID(1), WindowID(2)])
    }

    @Test func pinnedSeparatorsAppearInPinOrder() {
        let a = PinnedApp(bundleID: "a", path: "/A.app", name: "A")
        let b = PinnedApp(bundleID: "b", path: "/B.app", name: "B")
        let separator = PinnedApp.separator(id: "s1")
        let items = TaskbarLayoutBuilder.build(TaskbarInput(apps: [], windows: [], pins: [a, separator, b], policy: GroupingPolicy()))
        #expect(items.map(\.kind) == [.launcher, .separator, .launcher])
        #expect(items[1].id == "sep:s1" && items[1].isPinned)
    }

    @Test func automaticSeparatorSitsBetweenPinnedAndOtherApps() {
        let pin = PinnedApp(bundleID: Fixture.safari, path: "/Applications/Safari.app", name: "Safari")
        let apps = [Fixture.app(1, Fixture.safari, name: "Safari", sequence: 1), Fixture.app(2, Fixture.terminal, name: "Terminal", sequence: 2)]
        var input = TaskbarInput(apps: apps, windows: [], pins: [pin], policy: GroupingPolicy(), separatorAfterPinned: true)
        let items = TaskbarLayoutBuilder.build(input)
        #expect(items.map(\.kind) == [.application, .separator, .application])
        #expect(items[1].id == TaskbarLayoutBuilder.autoSeparatorID && !items[1].isPinned)

        input.apps = [apps[0]]
        #expect(!TaskbarLayoutBuilder.build(input).contains { $0.kind == .separator })
        input.separatorAfterPinned = false
        input.apps = apps
        #expect(!TaskbarLayoutBuilder.build(input).contains { $0.kind == .separator })
    }

    @Test func separatorsNeverMatchApps() {
        let separator = PinnedApp.separator(id: "x")
        #expect(!separator.matches(Fixture.app(1, nil)))
        #expect(separator.key == "sep:x")
    }
}

@Suite("Downloads and Trash")
struct SystemItemTests {
    let app = Fixture.app(1, Fixture.safari, name: "Safari")

    @Test func appearAtTheEndAfterASeparator() {
        let input = TaskbarInput(apps: [app], windows: [], pins: [], policy: GroupingPolicy(), showDownloads: true, showTrash: true)
        let items = TaskbarLayoutBuilder.build(input)
        #expect(items.map(\.kind) == [.application, .separator, .downloads, .trash])
        #expect(items[1].id == TaskbarLayoutBuilder.systemSeparatorID)
        #expect(items.suffix(3).allSatisfy(TaskbarLayoutBuilder.isFixed))
    }

    @Test func eachCanBeTurnedOff() {
        var input = TaskbarInput(apps: [app], windows: [], pins: [], policy: GroupingPolicy(), showDownloads: false, showTrash: true)
        #expect(TaskbarLayoutBuilder.build(input).map(\.kind) == [.application, .separator, .trash])
        input.showTrash = false
        #expect(TaskbarLayoutBuilder.build(input).map(\.kind) == [.application])
    }

    @Test func noLeadingSeparatorWhenBarIsOtherwiseEmpty() {
        let input = TaskbarInput(apps: [], windows: [], pins: [], policy: GroupingPolicy(), showDownloads: true, showTrash: true)
        #expect(TaskbarLayoutBuilder.build(input).map(\.kind) == [.downloads, .trash])
    }

    @Test func pinnedSeparatorsAndAppsStayMovable() {
        let pinnedSeparator = TaskbarLayoutBuilder.separator(id: "sep:x", isPinned: true)
        #expect(!TaskbarLayoutBuilder.isFixed(pinnedSeparator))
        #expect(TaskbarLayoutBuilder.isFixed(TaskbarLayoutBuilder.separator(id: TaskbarLayoutBuilder.autoSeparatorID, isPinned: false)))
    }

    @Test func defaultsShowBoth() {
        let appearance = AppearanceSettings()
        #expect(appearance.showDownloads && appearance.showTrash)
    }
}
