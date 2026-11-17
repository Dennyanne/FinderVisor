import ApplicationServices
import CoreGraphics

/// Accessibility access to Finder's windows. All calls are main-actor; every element gets a 0.5 s messaging timeout.
@MainActor
protocol AXWindowService {
    /// Finder's windows (`AXWindows`): one element per tab group (the selected tab), minimized windows included.
    func windows(ofApp pid: pid_t) -> [AXUIElement]
    func focusedWindow(ofApp pid: pid_t) -> AXUIElement?
    func position(of window: AXUIElement) -> CGPoint?
    /// Live frame in global top-left coordinates (minimized windows report their restored frame).
    func frame(of window: AXUIElement) -> CGRect?
    func isMinimized(_ window: AXUIElement) -> Bool?
    func title(of window: AXUIElement) -> String?
    /// False when the element is gone (`kAXErrorInvalidUIElement`) or unreadable.
    func isValid(_ window: AXUIElement) -> Bool
    @discardableResult func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> Bool
    /// Position → size → position (Finder may clamp the first set).
    func setFrame(_ window: AXUIElement, _ frame: CGRect)
    /// `AXRaise` + `AXMain = true`.
    func raise(_ window: AXUIElement)
    /// `AXFrontmost = true` on the application element.
    @discardableResult func setFrontmost(pid: pid_t) -> Bool
}

final class LiveAXWindowService: AXWindowService {
    static let messagingTimeout: Float = 0.5

    func windows(ofApp pid: pid_t) -> [AXUIElement] {
        elements(application(pid), kAXWindowsAttribute).map(withTimeout)
    }

    func focusedWindow(ofApp pid: pid_t) -> AXUIElement? {
        element(application(pid), kAXFocusedWindowAttribute).map(withTimeout)
    }

    func position(of window: AXUIElement) -> CGPoint? {
        guard let position = axValue(window, kAXPositionAttribute) else { return nil }
        var origin = CGPoint.zero
        return AXValueGetValue(position, .cgPoint, &origin) ? origin : nil
    }

    func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute), let size = axValue(window, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    func isMinimized(_ window: AXUIElement) -> Bool? {
        (copy(window, kAXMinimizedAttribute) as? NSNumber)?.boolValue
    }

    func title(of window: AXUIElement) -> String? {
        copy(window, kAXTitleAttribute) as? String
    }

    func isValid(_ window: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success
    }

    @discardableResult func setMinimized(_ window: AXUIElement, _ minimized: Bool) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized as CFBoolean) == .success
    }

    func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    @discardableResult func setFrontmost(pid: pid_t) -> Bool {
        AXUIElementSetAttributeValue(application(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
    }

    // MARK: - Helpers

    private func application(_ pid: pid_t) -> AXUIElement {
        withTimeout(AXUIElementCreateApplication(pid))
    }

    private func withTimeout(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func elements(_ parent: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = copy(parent, attribute) as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
        }
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXValue.self)
    }
}
