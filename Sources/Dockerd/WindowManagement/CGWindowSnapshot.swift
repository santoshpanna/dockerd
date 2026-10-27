import CoreGraphics
import DockerdCore
import Foundation

struct CGWindowSnapshot {
    let byPID: [pid_t: [CGWindowRecord]]
    let aliveIDs: Set<UInt32>

    static let empty = CGWindowSnapshot(byPID: [:], aliveIDs: [])

    static func capture() -> CGWindowSnapshot {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return .empty
        }
        var byPID: [pid_t: [CGWindowRecord]] = [:]
        var alive = Set<UInt32>()
        for entry in list {
            guard
                let number = entry[kCGWindowNumber as String] as? NSNumber,
                let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = entry[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let record = CGWindowRecord(
                id: number.uint32Value,
                pid: owner.int32Value,
                bounds: bounds,
                layer: layer.intValue,
                isOnScreen: onScreen)
            byPID[record.pid, default: []].append(record)
            alive.insert(record.id)
        }
        return CGWindowSnapshot(byPID: byPID, aliveIDs: alive)
    }
}
