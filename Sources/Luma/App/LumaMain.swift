import AppKit
import Darwin

@main
@MainActor
struct LumaMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTestRunner.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
