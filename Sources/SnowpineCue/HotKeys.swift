import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts that work while another app (Zoom, Keynote) is in front.
/// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var references: [EventHotKeyRef] = []
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// Control + Option, the modifier pair every Snowpine Cue shortcut uses.
    static let controlOption = UInt32(controlKey | optionKey)

    @discardableResult
    static func register(keyCode: Int, modifiers: UInt32 = controlOption, _ handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_5043), id: id)  // "SNPC"
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        handlers[id] = handler
        references.append(reference)
        return true
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeys.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
