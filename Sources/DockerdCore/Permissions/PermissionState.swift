import Foundation

public enum AccessibilityPermission: String, Equatable, Sendable {
    case unknown
    case granted
    case denied
    case revoked

    public var isGranted: Bool { self == .granted }
}

public struct PermissionStateMachine: Sendable {
    public private(set) var state: AccessibilityPermission = .unknown

    public init(state: AccessibilityPermission = .unknown) {
        self.state = state
    }

    @discardableResult
    public mutating func update(trusted: Bool) -> AccessibilityPermission? {
        let next: AccessibilityPermission
        if trusted {
            next = .granted
        } else {
            switch state {
            case .granted, .revoked: next = .revoked
            case .unknown, .denied: next = .denied
            }
        }
        guard next != state else { return nil }
        state = next
        return next
    }
}
