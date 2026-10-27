import CoreGraphics
import Foundation
@testable import DockerdCore

enum Fixture {
    static func app(
        _ pid: pid_t,
        _ bundleID: String?,
        name: String? = nil,
        hidden: Bool = false,
        active: Bool = false,
        sequence: UInt64? = nil
    ) -> AppInfo {
        AppInfo(
            pid: pid,
            bundleID: bundleID,
            name: name ?? bundleID ?? "App\(pid)",
            bundlePath: bundleID.map { "/Applications/\($0).app" },
            isHidden: hidden,
            isActive: active,
            launchSequence: sequence ?? UInt64(pid))
    }

    static func window(
        _ id: UInt64,
        pid: pid_t,
        bundleID: String?,
        title: String,
        frame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
        presence: WindowPresence = .onScreen,
        focused: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: WindowID(id),
            pid: pid,
            bundleID: bundleID,
            appName: bundleID ?? "App",
            title: title,
            frame: frame,
            isMinimized: presence == .minimized,
            isFocused: focused,
            presence: presence)
    }

    static func snapshot(_ title: String, frame: CGRect? = CGRect(x: 0, y: 0, width: 500, height: 400), minimized: Bool = false, focused: Bool = false) -> WindowSnapshot {
        WindowSnapshot(title: title, frame: frame, isMinimized: minimized, isFocused: focused)
    }

    static func display(_ id: UInt32, x: CGFloat, primary: Bool = false) -> DisplayInfo {
        DisplayInfo(id: id, uuid: "uuid-\(id)", name: "Display \(id)", frame: CGRect(x: x, y: 0, width: 1920, height: 1080), isPrimary: primary)
    }

    static let vscode = "com.microsoft.VSCode"
    static let insiders = "com.microsoft.VSCodeInsiders"
    static let safari = "com.apple.Safari"
    static let terminal = "com.apple.Terminal"
}
