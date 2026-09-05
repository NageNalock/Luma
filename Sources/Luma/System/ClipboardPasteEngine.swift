import ApplicationServices

enum ClipboardPasteError: LocalizedError {
    case targetNotRunning
    case accessibilityPermissionRequired
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .targetNotRunning:
            return "原应用已经退出；内容已放回剪贴板。"
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限才能自动粘贴；内容已放回剪贴板，可手动按 ⌘V。"
        case .pasteFailed:
            return "自动粘贴失败；内容已放回剪贴板，可手动按 ⌘V。"
        }
    }
}

final class ClipboardPasteEngine {
    func paste(to context: SourceContext) -> Result<Void, Error> {
        guard !context.application.isTerminated else {
            return .failure(ClipboardPasteError.targetNotRunning)
        }
        guard SendTextEngine.isAccessibilityTrusted(prompt: false) else {
            return .failure(ClipboardPasteError.accessibilityPermissionRequired)
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
