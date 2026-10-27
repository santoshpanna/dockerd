import AppKit
import ApplicationServices

extension AXUIElement {
    func copyValue(_ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        return (error, value)
    }

    func value(_ attribute: String) -> CFTypeRef? {
        let (error, value) = copyValue(attribute)
        return error == .success ? value : nil
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        guard let value = value(attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    var frame: CGRect? {
        guard let origin = point(kAXPositionAttribute), let size = size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    func set(_ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)!)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(self, action as CFString)
    }

    var processID: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }
}

enum AXWindowFilter {
    static func isUserWindow(_ element: AXUIElement) -> Bool {
        guard element.string(kAXRoleAttribute) == kAXWindowRole else { return false }
        let subrole = element.string(kAXSubroleAttribute)
        if subrole == kAXStandardWindowSubrole { return true }
        if subrole == kAXFloatingWindowSubrole || subrole == kAXSystemDialogSubrole || subrole == kAXSystemFloatingWindowSubrole {
            return false
        }
        return element.element(kAXMinimizeButtonAttribute) != nil
    }
}
