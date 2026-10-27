import AppKit
import os

enum SystemFolders {
    static let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    static let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
    static let recentLimit = 20

    private static let logger = Logger(subsystem: "me.santoshpanna.Dockerd", category: "folders")

    static func recentDownloads() -> Result<[URL], Error> {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: downloads, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            let dated = urls.map { url -> (URL, Date) in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return (url, values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast)
            }
            return .success(dated.sorted { $0.1 > $1.1 }.prefix(recentLimit).map(\.0))
        } catch {
            logger.error("Could not list Downloads: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    static func downloadsMenu() -> NSMenu {
        let menu = NSMenu(title: "Downloads")
        menu.autoenablesItems = false
        switch recentDownloads() {
        case .success(let urls) where urls.isEmpty:
            let empty = NSMenuItem(title: "No downloads", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        case .success(let urls):
            for url in urls {
                let item = ClosureMenuItem(url.lastPathComponent) { NSWorkspace.shared.open(url) }
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
        case .failure:
            let denied = NSMenuItem(title: "Dockerd can't read Downloads — allow it in Privacy & Security › Files and Folders", action: nil, keyEquivalent: "")
            denied.isEnabled = false
            menu.addItem(denied)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open Downloads Folder") { NSWorkspace.shared.open(downloads) })
        return menu
    }

    static func openTrash() {
        NSWorkspace.shared.open(trash)
    }

    static func trashIsEmpty() -> Bool? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else { return nil }
        return contents.allSatisfy { $0.hasPrefix(".") }
    }

    static func confirmEmptyTrash() {
        AppActivation.bringSelfForward()
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to permanently erase the items in the Trash?"
        alert.informativeText = "You can't undo this action. Finder will empty the Trash."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error {
            logger.error("Empty Trash failed: \(error, privacy: .public)")
            let failure = NSAlert()
            failure.messageText = "Couldn't empty the Trash"
            failure.informativeText = "Allow Dockerd to control Finder in System Settings › Privacy & Security › Automation, then try again."
            failure.runModal()
        }
    }
}
