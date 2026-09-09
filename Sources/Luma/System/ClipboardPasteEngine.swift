import AppKit
import ApplicationServices

enum ClipboardPasteError: LocalizedError {
    case targetNotRunning
    case accessibilityPermissionRequired
    case targetChanged
    case clipboardChanged
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .targetNotRunning:
            return "原应用已经退出；内容已放回剪贴板。"
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限才能自动粘贴；内容已放回剪贴板，可手动按 ⌘V。"
        case .targetChanged:
            return "发送目标已经变化；内容已复制，可手动按 ⌘V。"
        case .clipboardChanged:
            return "剪贴板内容已变化，本次自动粘贴已取消。"
        case .pasteFailed:
            return "自动粘贴失败；内容已放回剪贴板，可手动按 ⌘V。"
        }
    }
}

final class ClipboardPasteEngine {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func paste(to context: SourceContext, expectedChangeCount: Int) -> Result<Void, Error> {
        guard !context.application.isTerminated else {
            return .failure(ClipboardPasteError.targetNotRunning)
        }
        guard Self.isAccessibilityTrusted(prompt: false) else {
            return .failure(ClipboardPasteError.accessibilityPermissionRequired)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processIdentifier else {
            return .failure(ClipboardPasteError.targetChanged)
        }
        guard NSPasteboard.general.changeCount == expectedChangeCount else {
            return .failure(ClipboardPasteError.clipboardChanged)
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .failure(ClipboardPasteError.pasteFailed)
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(context.processIdentifier)
        keyUp.postToPid(context.processIdentifier)
        return .success(())
    }
}
