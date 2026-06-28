import AppKit
import Carbon

class HotKeyManager {
  static let shared = HotKeyManager()

  private struct Registration {
    let id: UInt32
    var reference: EventHotKeyRef?
  }

  private var handlers: [UInt32: () -> Void] = [:]
  private var registrations: [HotkeyIdentifier: Registration] = [:]
  private var heldHotKeyIds: Set<UInt32> = []
  private var currentId: UInt32 = 1

  private init() {
    installEventHandler()
  }

  func register(
    identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void
  ) {
    unregister(identifier: identifier)

    let id = currentId
    currentId &+= 1

    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: 0x1111, id: id)
    let status = RegisterEventHotKey(
      combination.keyCode, combination.modifiers, hotKeyID, GetEventDispatcherTarget(), 0,
      &hotKeyRef)

    guard status == noErr else {
      print("Failed to register hotkey for \(identifier) status=\(status)")
      return
    }

    handlers[id] = handler
    registrations[identifier] = Registration(id: id, reference: hotKeyRef)
  }

  func unregister(identifier: HotkeyIdentifier) {
    guard let registration = registrations.removeValue(forKey: identifier) else { return }
    handlers.removeValue(forKey: registration.id)
    if let reference = registration.reference {
      UnregisterEventHotKey(reference)
    }
  }

  func unregisterAll() {
    for (_, registration) in registrations {
      if let reference = registration.reference {
        UnregisterEventHotKey(reference)
      }
    }
    registrations.removeAll()
    handlers.removeAll()
  }

  private func installEventHandler() {
    var eventSpecs = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]

    InstallEventHandler(
      GetEventDispatcherTarget(),
      { (_, event, _) -> OSStatus in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

        let manager = HotKeyManager.shared
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
          guard !manager.heldHotKeyIds.contains(hotKeyID.id) else { return noErr }
          manager.heldHotKeyIds.insert(hotKeyID.id)
          manager.handlers[hotKeyID.id]?()
        case UInt32(kEventHotKeyReleased):
          manager.heldHotKeyIds.remove(hotKeyID.id)
        default:
          break
        }

        return noErr
      }, 2, &eventSpecs, nil, nil)
  }
}
