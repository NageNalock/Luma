import AppKit

enum SourceContextCapture {
    static func capture(excludingBundleIdentifier: String?) -> SourceContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        if application.bundleIdentifier == excludingBundleIdentifier { return nil }

        return SourceContext(
            application: application,
            capturedAt: Date()
        )
    }
}
