import CoreGraphics
import Foundation

public struct CGWindowRecord: Equatable, Sendable {
    public var id: UInt32
    public var pid: pid_t
    public var bounds: CGRect
    public var layer: Int
    public var isOnScreen: Bool

    public init(id: UInt32, pid: pid_t, bounds: CGRect, layer: Int = 0, isOnScreen: Bool) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

public enum CGWindowMatcher {
    public static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height))
    }

    public static func match(
        frames: [Int: CGRect],
        candidates: [CGWindowRecord],
        hints: [Int: UInt32] = [:],
        tolerance: CGFloat = 2
    ) -> [Int: CGWindowRecord] {
        var result: [Int: CGWindowRecord] = [:]
        var used = Set<UInt32>()
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (index, hinted) in hints.sorted(by: { $0.key < $1.key }) {
            guard let frame = frames[index], let candidate = byID[hinted], !used.contains(hinted) else { continue }
            if distance(frame, candidate.bounds) <= tolerance {
                result[index] = candidate
                used.insert(hinted)
            }
        }

        var pairs: [(index: Int, candidate: CGWindowRecord, distance: CGFloat)] = []
        for (index, frame) in frames where result[index] == nil {
            for candidate in candidates where !used.contains(candidate.id) {
                let d = distance(frame, candidate.bounds)
                if d <= tolerance { pairs.append((index, candidate, d)) }
            }
        }
        pairs.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.candidate.id < $1.candidate.id
        }
        for pair in pairs where result[pair.index] == nil && !used.contains(pair.candidate.id) {
            result[pair.index] = pair.candidate
            used.insert(pair.candidate.id)
        }
        return result
    }
}
