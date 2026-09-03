import AppKit
import ApplicationServices

enum SourceContextCapture {
    static func capture(excludingBundleIdentifier: String?) -> SourceContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        if application.bundleIdentifier == excludingBundleIdentifier { return nil }

        var focusedElement: CFTypeRef?
        let systemElement = AXUIElementCreateSystemWide()
        let status = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        return SourceContext(
            application: application,
            focusedElement: status == .success ? (focusedElement as! AXUIElement?) : nil,
            capturedAt: Date()
        )
    }
}
