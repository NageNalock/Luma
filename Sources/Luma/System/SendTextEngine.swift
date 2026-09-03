import AppKit
import ApplicationServices

enum SendTextMethod: String {
    case accessibility = "辅助功能"
    case keyEvents = "键盘事件"
}

enum SendTextError: LocalizedError {
    case accessibilityPermissionRequired
    case targetNotRunning
    case targetChanged
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限，才能把文本发送到其他应用。"
        case .targetNotRunning:
            return "原应用已经退出。"
        case .targetChanged:
            return "发送目标已经变化，本次操作已取消。"
        case .sendFailed:
            return "目标应用没有接受文本。"
        }
    }
}

final class SendTextEngine {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func send(_ text: String, to context: SourceContext) -> Result<SendTextMethod, Error> {
        guard !context.application.isTerminated else {
            return .failure(SendTextError.targetNotRunning)
        }
        guard Self.isAccessibilityTrusted(prompt: false) else {
            return .failure(SendTextError.accessibilityPermissionRequired)
        }

        if let focusedElement = context.focusedElement {
            let status = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if status == .success {
                return .success(.accessibility)
            }
        }

        guard sendAsKeyEvents(text, processIdentifier: context.processIdentifier) else {
            return .failure(SendTextError.sendFailed)
        }
        return .success(.keyEvents)
    }

    private func sendAsKeyEvents(_ text: String, processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        var buffer = ""
        func flush() -> Bool {
            guard !buffer.isEmpty else { return true }
            let succeeded = postUnicode(buffer, source: source, processIdentifier: processIdentifier)
            buffer.removeAll(keepingCapacity: true)
            return succeeded
        }

        for character in text {
            let keyCode: CGKeyCode?
            switch character {
            case "\n", "\r": keyCode = 36
            case "\t": keyCode = 48
            case Character(UnicodeScalar(27)): keyCode = 53
            default: keyCode = nil
            }

            if let keyCode {
                guard flush(), postKey(keyCode, source: source, processIdentifier: processIdentifier) else {
                    return false
                }
            } else {
                buffer.append(character)
                if buffer.utf16.count >= 16, !flush() { return false }
            }
        }

        return flush()
    }

    private func postUnicode(_ text: String, source: CGEventSource, processIdentifier: pid_t) -> Bool {
        let units = Array(text.utf16)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return false }

        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.0015)
        return true
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource, processIdentifier: pid_t) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }

        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.0015)
        return true
    }
}
