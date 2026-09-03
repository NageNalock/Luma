import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: Handler

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey), handler: @escaping Handler) throws {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            lumaHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            throw GlobalHotKeyError.installFailed(installStatus)
        }

        let identifier = EventHotKeyID(signature: OSType(0x4C554D41), id: 1) // LUMA
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
            throw GlobalHotKeyError.registrationFailed(registerStatus)
        }
    }

    fileprivate func invoke() {
        DispatchQueue.main.async { [handler] in handler() }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

private let lumaHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().invoke()
    return noErr
}

enum GlobalHotKeyError: LocalizedError {
    case installFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installFailed(let status):
            return "无法安装全局快捷键处理器（\(status)）。"
        case .registrationFailed(let status):
            return "⌥ Space 已被其他应用占用（\(status)）。"
        }
    }
}
