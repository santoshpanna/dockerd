import AppKit
import DockerdCore

final class DockBadgeReader {
    static let interval: TimeInterval = 2
    private static let dockBundleID = "com.apple.dock"

    var onChange: (([DockBadge]) -> Void)?
    private(set) var badges: [DockBadge] = []
    private var timer: Timer?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
            publish([])
        }
    }

    private func refresh() {
        publish(Self.read())
    }

    private func publish(_ next: [DockBadge]) {
        guard next != badges else { return }
        badges = next
        onChange?(next)
    }

    private static func read() -> [DockBadge] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first else { return [] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        var result: [DockBadge] = []
        for list in children(of: root) {
            AXUIElementSetMessagingTimeout(list, 0.25)
            for item in children(of: list) {
                AXUIElementSetMessagingTimeout(item, 0.25)
                guard item.string(kAXSubroleAttribute) == "AXApplicationDockItem",
                      let label = item.string("AXStatusLabel"), !label.isEmpty
                else { continue }
                let url = item.value(kAXURLAttribute) as? URL
                result.append(DockBadge(path: url?.path, name: item.string(kAXTitleAttribute) ?? "", label: label))
            }
        }
        return result
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (element.value(kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
