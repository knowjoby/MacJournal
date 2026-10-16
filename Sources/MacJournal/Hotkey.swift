import Carbon

final class PauseHotkey {
    var handler: EventHandlerRef?
    var reference: EventHotKeyRef?
    var action: (() -> Void)?
    init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<PauseHotkey>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | shiftKey | optionKey), EventHotKeyID(signature: 0x4D4A5048, id: 1), GetApplicationEventTarget(), 0, &reference)
        if status != noErr { self.action = nil }
    }
    var registered: Bool { reference != nil }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
