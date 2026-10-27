import CoreGraphics
import Testing
@testable import DockerdCore

@Suite("Window store")
struct WindowStoreTests {
    typealias Store = WindowStore<String>
    let app = Fixture.app(42, Fixture.vscode)

    @Test func assignsStableIDsAcrossRefreshes() {
        var store = Store()
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("repo-a")),
            ObservedWindow(element: "b", snapshot: Fixture.snapshot("repo-b")),
        ])
        let first = store.windows.map(\.id)
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "b", snapshot: Fixture.snapshot("repo-b renamed")),
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("repo-a")),
        ])
        #expect(store.windows.map(\.id) == first)
        #expect(store.window(first[1])?.title == "repo-b renamed")
    }

    @Test func identicalTitlesGetDistinctIdentities() {
        var store = Store()
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "x", snapshot: Fixture.snapshot("Untitled")),
            ObservedWindow(element: "y", snapshot: Fixture.snapshot("Untitled")),
        ])
        #expect(store.count == 2)
        #expect(store.element(for: store.windows[0].id) == "x")
        #expect(store.element(for: store.windows[1].id) == "y")
    }

    @Test func closedWindowsAreRemoved() {
        var store = Store()
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("a")),
            ObservedWindow(element: "b", snapshot: Fixture.snapshot("b")),
        ])
        let changed = store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"))])
        #expect(changed)
        #expect(store.windows.map(\.title) == ["a"])
        #expect(store.id(for: "b") == nil)
    }

    @Test func destroyedNotificationRemovesImmediately() {
        var store = Store()
        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"))])
        let removed = store.removeWindow(element: "a")
        #expect(removed)
        #expect(store.count == 0)
        let removedAgain = store.removeWindow(element: "a")
        #expect(!removedAgain)
    }

    @Test func terminatedAppDropsAllItsWindows() {
        var store = Store()
        let other = Fixture.app(7, Fixture.safari)
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("a")),
            ObservedWindow(element: "b", snapshot: Fixture.snapshot("b")),
        ])
        store.reconcile(app: other, observed: [ObservedWindow(element: "s", snapshot: Fixture.snapshot("s"))])
        let removedApp = store.removeApp(pid: app.pid)
        #expect(removedApp)
        #expect(store.windows.map(\.pid) == [7])
        let retainedNone = store.retainApps([])
        #expect(retainedNone)
        #expect(store.count == 0)
    }

    @Test func minimizeAndRestoreUpdatePresence() {
        var store = Store()
        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), isOnScreen: true)])
        #expect(store.windows[0].presence == .onScreen)
        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a", minimized: true), isOnScreen: false)])
        #expect(store.windows[0].presence == .minimized)
        #expect(store.windows[0].isMinimized)
        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), isOnScreen: true)])
        #expect(store.windows[0].presence == .onScreen)
    }

    @Test func hiddenAppMarksWindowsHidden() {
        var store = Store()
        let hidden = Fixture.app(42, Fixture.vscode, hidden: true)
        store.reconcile(app: hidden, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), isOnScreen: false)])
        #expect(store.windows[0].presence == .hidden)
    }

    @Test func windowsOnAnotherSpaceAreRetainedWhileTheyExist() {
        var store = Store()
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), cgWindowID: 100, isOnScreen: true),
            ObservedWindow(element: "b", snapshot: Fixture.snapshot("b"), cgWindowID: 101, isOnScreen: true),
        ])
        let idB = store.id(for: "b")
        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), cgWindowID: 100, isOnScreen: true)]) {
            $0 == 101
        }
        #expect(store.count == 2)
        #expect(store.window(idB!)?.presence == .otherSpace)

        store.reconcile(app: app, observed: [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), cgWindowID: 100, isOnScreen: true)]) { _ in
            false
        }
        #expect(store.count == 1)
    }

    @Test func rebindsWindowWhenElementChangesButCGWindowMatches() {
        var store = Store()
        store.reconcile(app: app, observed: [ObservedWindow(element: "old", snapshot: Fixture.snapshot("a"), cgWindowID: 55, isOnScreen: true)])
        let id = store.id(for: "old")
        store.reconcile(app: app, observed: [ObservedWindow(element: "new", snapshot: Fixture.snapshot("a"), cgWindowID: 55, isOnScreen: true)])
        #expect(store.count == 1)
        #expect(store.id(for: "new") == id)
        #expect(store.id(for: "old") == nil)
    }

    @Test func unchangedRefreshReportsNoChange() {
        var store = Store()
        let observed = [ObservedWindow(element: "a", snapshot: Fixture.snapshot("a"), isOnScreen: true)]
        let firstChanged = store.reconcile(app: app, observed: observed)
        #expect(firstChanged)
        let secondChanged = store.reconcile(app: app, observed: observed)
        #expect(!secondChanged)
    }

    @Test func duplicateElementsInOneRefreshAreCountedOnce() {
        var store = Store()
        store.reconcile(app: app, observed: [
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("a")),
            ObservedWindow(element: "a", snapshot: Fixture.snapshot("a")),
        ])
        #expect(store.count == 1)
    }
}

@Suite("CGWindow matching")
struct CGWindowMatcherTests {
    @Test func matchesExactFrames() {
        let frames = [0: CGRect(x: 0, y: 0, width: 800, height: 600), 1: CGRect(x: 50, y: 50, width: 800, height: 600)]
        let candidates = [
            CGWindowRecord(id: 2, pid: 1, bounds: CGRect(x: 50, y: 50, width: 800, height: 600), isOnScreen: true),
            CGWindowRecord(id: 1, pid: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true),
        ]
        let result = CGWindowMatcher.match(frames: frames, candidates: candidates)
        #expect(result[0]?.id == 1)
        #expect(result[1]?.id == 2)
    }

    @Test func ignoresFramesBeyondTolerance() {
        let result = CGWindowMatcher.match(
            frames: [0: CGRect(x: 0, y: 0, width: 800, height: 600)],
            candidates: [CGWindowRecord(id: 1, pid: 1, bounds: CGRect(x: 30, y: 0, width: 800, height: 600), isOnScreen: true)])
        #expect(result.isEmpty)
    }

    @Test func hintsKeepAssignmentsStableForIdenticalFrames() {
        let frame = CGRect(x: 10, y: 10, width: 900, height: 700)
        let candidates = [
            CGWindowRecord(id: 10, pid: 1, bounds: frame, isOnScreen: true),
            CGWindowRecord(id: 11, pid: 1, bounds: frame, isOnScreen: true),
        ]
        let result = CGWindowMatcher.match(frames: [0: frame, 1: frame], candidates: candidates, hints: [0: 11, 1: 10])
        #expect(result[0]?.id == 11)
        #expect(result[1]?.id == 10)
    }

    @Test func eachCandidateIsUsedOnce() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let result = CGWindowMatcher.match(
            frames: [0: frame, 1: frame],
            candidates: [CGWindowRecord(id: 1, pid: 1, bounds: frame, isOnScreen: true)])
        #expect(result.count == 1)
    }
}
