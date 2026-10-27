import Foundation

public enum GroupingMode: String, Codable, CaseIterable, Sendable {
    case grouped
    case ungrouped
}

public struct GroupingRule: Equatable, Sendable {
    public var bundleID: String
    public var mode: GroupingMode
}

public struct GroupingPolicy: Codable, Equatable, Sendable {
    public var defaultMode: GroupingMode
    public private(set) var rules: [String: GroupingMode]

    public init(defaultMode: GroupingMode = .grouped, rules: [String: GroupingMode] = [:]) {
        self.defaultMode = defaultMode
        self.rules = [:]
        for (bundleID, mode) in rules {
            setMode(mode, for: bundleID)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case defaultMode
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultMode = (try? container.decodeIfPresent(GroupingMode.self, forKey: .defaultMode)) ?? .grouped
        let raw = (try? container.decodeIfPresent([String: String].self, forKey: .rules)) ?? [:]
        var rules: [String: GroupingMode] = [:]
        for (bundleID, value) in raw {
            if let mode = GroupingMode(rawValue: value) { rules[bundleID] = mode }
        }
        self.init(defaultMode: defaultMode, rules: rules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultMode, forKey: .defaultMode)
        try container.encode(rules.mapValues(\.rawValue), forKey: .rules)
    }

    public func explicitMode(for bundleID: String?) -> GroupingMode? {
        guard let key = Self.normalize(bundleID) else { return nil }
        return rules[key]
    }

    public func mode(for bundleID: String?) -> GroupingMode {
        explicitMode(for: bundleID) ?? defaultMode
    }

    public mutating func setMode(_ mode: GroupingMode?, for bundleID: String) {
        guard let key = Self.normalize(bundleID) else { return }
        rules[key] = mode
    }

    public var sortedRules: [GroupingRule] {
        rules.map { GroupingRule(bundleID: $0.key, mode: $0.value) }.sorted { $0.bundleID < $1.bundleID }
    }

    static func normalize(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}
