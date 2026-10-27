import CoreGraphics
import Testing
@testable import DockerdCore

@Suite("Displays")
struct DisplayTests {
    let left = Fixture.display(1, x: 0, primary: true)
    let right = Fixture.display(2, x: 1920)

    @Test func assignsWindowToDisplayWithLargestOverlap() {
        let frame = CGRect(x: 1700, y: 100, width: 800, height: 600)
        #expect(WindowDisplayAssigner.display(for: frame, among: [left, right])?.id == 2)
        let mostlyLeft = CGRect(x: 1500, y: 100, width: 600, height: 600)
        #expect(WindowDisplayAssigner.display(for: mostlyLeft, among: [left, right])?.id == 1)
    }

    @Test func unknownFrameFallsBackToPrimary() {
        #expect(WindowDisplayAssigner.display(for: nil, among: [right, left])?.id == 1)
    }

    @Test func offscreenWindowGoesToNearestDisplay() {
        let frame = CGRect(x: 4200, y: 100, width: 200, height: 200)
        #expect(WindowDisplayAssigner.display(for: frame, among: [left, right])?.id == 2)
    }

    @Test func windowsAppearOnlyOnTheirDisplayDock() {
        var policy = GroupingPolicy()
        policy.setMode(.ungrouped, for: Fixture.vscode)
        let apps = [Fixture.app(1, Fixture.vscode)]
        let windows = [
            Fixture.window(1, pid: 1, bundleID: Fixture.vscode, title: "left", frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
            Fixture.window(2, pid: 1, bundleID: Fixture.vscode, title: "right", frame: CGRect(x: 2100, y: 100, width: 800, height: 600)),
        ]
        func items(on display: DisplayInfo, placement: WindowPlacement = .ownDisplay) -> [String] {
            TaskbarLayoutBuilder.build(TaskbarInput(
                apps: apps, windows: windows, pins: [], policy: policy,
                dockDisplays: [left, right], targetDisplayID: display.id, placement: placement)).map(\.title)
        }
        #expect(items(on: left) == ["left"])
        #expect(items(on: right) == ["right"])
        #expect(items(on: left, placement: .everyDisplay) == ["left", "right"])
    }

    @Test func groupedAppOnlyShowsWhereItHasWindowsUnlessPinned() {
        let apps = [Fixture.app(2, Fixture.safari)]
        let windows = [Fixture.window(1, pid: 2, bundleID: Fixture.safari, title: "s", frame: CGRect(x: 2000, y: 0, width: 500, height: 500))]
        func build(_ display: DisplayInfo, pins: [PinnedApp]) -> [DockItem] {
            TaskbarLayoutBuilder.build(TaskbarInput(
                apps: apps, windows: windows, pins: pins, policy: GroupingPolicy(),
                dockDisplays: [left, right], targetDisplayID: display.id))
        }
        #expect(build(left, pins: []).isEmpty)
        #expect(build(right, pins: []).first?.windows.count == 1)
        let pin = PinnedApp(bundleID: Fixture.safari, path: "/Applications/Safari.app", name: "Safari")
        let pinnedLeft = build(left, pins: [pin])
        #expect(pinnedLeft.count == 1)
        #expect(pinnedLeft[0].isRunning && pinnedLeft[0].windows.isEmpty)
    }

    @Test func removingADisplayReassignsItsWindows() {
        let windows = [Fixture.window(1, pid: 2, bundleID: Fixture.safari, title: "s", frame: CGRect(x: 2000, y: 0, width: 500, height: 500))]
        let items = TaskbarLayoutBuilder.build(TaskbarInput(
            apps: [Fixture.app(2, Fixture.safari)], windows: windows, pins: [], policy: GroupingPolicy(),
            dockDisplays: [left], targetDisplayID: left.id))
        #expect(items.first?.windows.count == 1)
    }

    @Test func currentSpaceOnlyHidesOtherSpaceWindows() {
        let windows = [
            Fixture.window(1, pid: 2, bundleID: Fixture.safari, title: "here"),
            Fixture.window(2, pid: 2, bundleID: Fixture.safari, title: "there", presence: .otherSpace),
            Fixture.window(3, pid: 2, bundleID: Fixture.safari, title: "min", presence: .minimized),
        ]
        let build = { (only: Bool) in
            TaskbarLayoutBuilder.build(TaskbarInput(
                apps: [Fixture.app(2, Fixture.safari)], windows: windows, pins: [], policy: GroupingPolicy(),
                currentSpaceOnly: only)).first?.windows.map(\.title) ?? []
        }
        #expect(build(false) == ["here", "there", "min"])
        #expect(build(true) == ["here", "min"])
    }

    @Test func dockDisplaySelection() {
        var settings = DisplaySettings()
        #expect(DockDisplaySelector.dockDisplays(all: [left, right], settings: settings).map(\.id) == [1, 2])
        settings.mode = .primary
        #expect(DockDisplaySelector.dockDisplays(all: [right, left], settings: settings).map(\.id) == [1])
        settings.mode = .selected
        settings.selectedDisplayUUIDs = ["uuid-2"]
        #expect(DockDisplaySelector.dockDisplays(all: [left, right], settings: settings).map(\.id) == [2])
        settings.selectedDisplayUUIDs = ["uuid-gone"]
        #expect(DockDisplaySelector.dockDisplays(all: [left, right], settings: settings).map(\.id) == [1])
        #expect(DockDisplaySelector.dockDisplays(all: [], settings: settings).isEmpty)
    }

    @Test func cocoaToTopLeftConversion() {
        let converted = DisplayGeometry.topLeftRect(fromCocoa: CGRect(x: 1920, y: 200, width: 1280, height: 800), primaryHeight: 1080)
        #expect(converted == CGRect(x: 1920, y: 80, width: 1280, height: 800))
    }

    @Test func panelFrameSitsFlushOnScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 80, width: 1920, height: 970)
        let bottom = DockGeometry.panelFrame(screenFrame: screen, visibleFrame: visible, edge: .bottom, length: 400, thickness: 70)
        #expect(bottom == CGRect(x: 760, y: 0, width: 400, height: 70))
        let left = DockGeometry.panelFrame(screenFrame: screen, visibleFrame: visible, edge: .left, length: 300, thickness: 70)
        #expect(left == CGRect(x: 0, y: 375, width: 70, height: 300))
        let right = DockGeometry.panelFrame(screenFrame: screen, visibleFrame: visible, edge: .right, length: 5000, thickness: 70)
        #expect(right == CGRect(x: 1850, y: 0, width: 70, height: 1050))
    }

    @Test func panelFrameFollowsSecondaryScreenOrigin() {
        let screen = CGRect(x: 1920, y: -200, width: 1280, height: 800)
        let bottom = DockGeometry.panelFrame(screenFrame: screen, visibleFrame: screen, edge: .bottom, length: 2000, thickness: 50)
        #expect(bottom == CGRect(x: 1920, y: -200, width: 1280, height: 50))
    }

    @Test func metricsScaleDownToFit() {
        var appearance = AppearanceSettings()
        appearance.iconSize = 48
        appearance.showWindowTitles = false
        let metrics = DockMetrics(appearance: appearance)
        let items = (0..<40).map { index in
            DockItem(id: "\(index)", kind: .application, appKey: "\(index)", bundleID: nil, bundlePath: nil,
                     appName: "", pids: [1], windows: [], isPinned: false, isActive: false, isHidden: false)
        }
        let scale = metrics.scale(toFit: items, available: 1000)
        #expect(scale < 1)
        #expect(metrics.contentLength(items, scale: scale) <= 1000.5 || scale == DockMetrics.minimumScale)
        #expect(metrics.scale(toFit: Array(items.prefix(3)), available: 1000) == 1)
    }

    @Test func titlesOnlyWidenWindowItemsOnBottomEdge() {
        var appearance = AppearanceSettings()
        appearance.showWindowTitles = true
        let window = DockItem(id: "w", kind: .window, appKey: "k", bundleID: nil, bundlePath: nil, appName: "",
                              pids: [1], windows: [], isPinned: false, isActive: false, isHidden: false)
        let bottom = DockMetrics(appearance: appearance)
        appearance.edge = .left
        let side = DockMetrics(appearance: appearance)
        #expect(bottom.extent(of: window) > side.extent(of: window))
    }
}

@Suite("Full-screen detection")
struct FullScreenCandidateTests {
    @Test func onlyWindowsFillingADisplayAreCandidates() {
        let main = Fixture.display(1, x: 0, primary: true)
        let side = Fixture.display(2, x: main.frame.width)
        let windows = [
            Fixture.window(1, pid: 1, bundleID: "video", title: "Movie", frame: main.frame),
            Fixture.window(2, pid: 2, bundleID: "code", title: "Repo", frame: CGRect(x: side.frame.minX + 10, y: 40, width: 800, height: 600)),
            Fixture.window(3, pid: 3, bundleID: "notch", title: "Below notch",
                           frame: CGRect(x: side.frame.minX, y: 38, width: side.frame.width, height: side.frame.height - 38)),
            Fixture.window(4, pid: 4, bundleID: "mini", title: "Minimized", frame: main.frame, presence: .minimized),
        ]
        let found = FullScreenCandidates.find(windows: windows, displays: [main, side])
        #expect(found.map(\.window) == [WindowID(1), WindowID(3)])
        #expect(found.map(\.display) == [1, 2])
    }
}
