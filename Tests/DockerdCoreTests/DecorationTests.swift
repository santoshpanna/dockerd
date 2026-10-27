import Foundation
import Testing
@testable import DockerdCore

@Suite("Badges and launch feedback")
struct DecorationTests {
    private func item(_ id: String, kind: DockItem.Kind, name: String, path: String?) -> DockItem {
        DockItem(
            id: id, kind: kind, appKey: id, bundleID: id, bundlePath: path, appName: name,
            pids: kind == .launcher ? [] : [1], windows: [], isPinned: false, isActive: false, isHidden: false)
    }

    @Test func badgeMatchesByPathThenName() {
        let items = [
            item("mail", kind: .application, name: "Mail", path: "/System/Applications/Mail.app"),
            item("safari", kind: .application, name: "Safari", path: "/Applications/Safari.app"),
            item("notes", kind: .application, name: "Notes", path: "/System/Applications/Notes.app"),
        ]
        let badges = [
            DockBadge(path: "/System/Applications/Mail.app", name: "Mail", label: "3"),
            DockBadge(path: "/Preboot/Safari.app", name: "Safari", label: "•"),
        ]
        let result = DockDecorations.apply(to: items, badges: badges, launching: [])
        #expect(result.map(\.badge) == ["3", "•", nil])
    }

    @Test func emptyLabelsAndSystemItemsGetNoBadge() {
        let items = [
            item("mail", kind: .application, name: "Mail", path: "/M.app"),
            item("sys:trash", kind: .trash, name: "Mail", path: nil),
        ]
        let result = DockDecorations.apply(to: items, badges: [DockBadge(path: "/M.app", name: "Mail", label: "")], launching: [])
        #expect(result.allSatisfy { $0.badge == nil })
        let named = DockDecorations.apply(to: items, badges: [DockBadge(path: nil, name: "Mail", label: "1")], launching: [])
        #expect(named.map(\.badge) == ["1", nil])
    }

    @Test func badgeFollowsEverySeparateWindowOfAnApp() {
        let items = [
            item("w1", kind: .window, name: "Code", path: "/Code.app"),
            item("w2", kind: .window, name: "Code", path: "/Code.app"),
        ]
        let result = DockDecorations.apply(to: items, badges: [DockBadge(path: "/Code.app", name: "Code", label: "2")], launching: [])
        #expect(result.map(\.badge) == ["2", "2"])
    }

    @Test func onlyLaunchersShowLaunching() {
        let items = [
            item("a", kind: .launcher, name: "A", path: "/A.app"),
            item("b", kind: .launcher, name: "B", path: "/B.app"),
            item("c", kind: .application, name: "C", path: "/C.app"),
        ]
        let result = DockDecorations.apply(to: items, badges: [], launching: ["/A.app", "/C.app"])
        #expect(result.map(\.isLaunching) == [true, false, false])
    }

    @Test func pathsAreNormalizedBeforeMatching() {
        let items = [item("a", kind: .launcher, name: "A", path: "/link/A.app")]
        let result = DockDecorations.apply(
            to: items, badges: [DockBadge(path: "/real/A.app", name: "x", label: "5")], launching: ["/real/A.app"],
            normalize: { $0.replacingOccurrences(of: "/link/", with: "/real/") })
        #expect(result[0].badge == "5")
        #expect(result[0].isLaunching)
    }

    @Test func launchSettlesWhenRunningOrTimedOut() {
        var tracker = LaunchTracker()
        let start = Date(timeIntervalSince1970: 1000)
        tracker.begin("/A.app", at: start)
        tracker.begin("/B.app", at: start)
        let early = tracker.settle(runningPaths: [], now: start.addingTimeInterval(1))
        #expect(!early)
        let launched = tracker.settle(runningPaths: ["/A.app"], now: start.addingTimeInterval(2))
        #expect(launched)
        #expect(tracker.paths == ["/B.app"])
        let expired = tracker.settle(runningPaths: [], now: start.addingTimeInterval(LaunchTracker.timeout))
        #expect(expired)
        #expect(tracker.paths.isEmpty)
    }
}
