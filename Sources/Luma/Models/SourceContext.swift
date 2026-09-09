import AppKit

struct SourceContext {
    let application: NSRunningApplication
    let capturedAt: Date

    var processIdentifier: pid_t { application.processIdentifier }
    var displayName: String { application.localizedName ?? "当前应用" }
    var bundleIdentifier: String { application.bundleIdentifier ?? "" }
    var icon: NSImage { application.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)! }
}
