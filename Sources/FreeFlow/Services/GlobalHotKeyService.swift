import Carbon
import Foundation
import FreeFlowCore

enum GlobalHotKeyError: LocalizedError {
  case inactiveRightOptionMonitor
  case installFailed(OSStatus)
  case invalidConfiguration
  case registrationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .inactiveRightOptionMonitor:
      "Right Option monitoring is not active."
    case .installFailed(let status):
      "Could not install the global hotkey handler (\(status))."
    case .invalidConfiguration:
      "A custom shortcut needs at least one modifier and one non-modifier key."
    case .registrationFailed(let status):
      "That shortcut could not be registered (\(status))."
    }
  }
}

@MainActor
final class GlobalHotKeyService {
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  var onFailure: ((String) -> Void)?

  private var eventHandlerRef: EventHandlerRef?
  private var hotKeyRef: EventHotKeyRef?
  private var rightOptionMonitor: RightOptionEventMonitor?
  private var registeredConfiguration: HotKeyConfiguration?
  private var isSuspended = false
  private var isShutdown = false

  var currentConfiguration: HotKeyConfiguration? { registeredConfiguration }

  init() throws {
    var eventTypes = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      ),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyReleased)
      ),
    ]

    let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
      InstallEventHandler(
        GetApplicationEventTarget(),
        Self.eventCallback,
        buffer.count,
        buffer.baseAddress,
        Unmanaged.passUnretained(self).toOpaque(),
        &eventHandlerRef
      )
    }
    guard status == noErr else {
      throw GlobalHotKeyError.installFailed(status)
    }
  }

  func register(_ configuration: HotKeyConfiguration) throws {
    if registeredConfiguration == configuration { return }

    if configuration.isRightOptionOnly {
      try registerRightOption(configuration)
      return
    }

    try registerCarbonHotKey(configuration)
  }

  func shutdown() {
    guard !isShutdown else { return }
    isShutdown = true

    rightOptionMonitor?.invalidate(notifyRelease: false)
    rightOptionMonitor = nil
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }
    registeredConfiguration = nil
  }

  func setSuspended(_ suspended: Bool) {
    guard suspended != isSuspended else { return }
    if suspended {
      onRelease?()
      isSuspended = true
      rightOptionMonitor?.suppressUntilPhysicalRelease()
    } else {
      rightOptionMonitor?.suppressUntilPhysicalRelease()
      isSuspended = false
    }
  }

  func handleSystemInterruption() {
    onRelease?()
    rightOptionMonitor?.suppressUntilPhysicalRelease()
  }

  func rearmAfterSystemInterruption() throws {
    guard
      !isShutdown,
      let configuration = registeredConfiguration,
      configuration.isRightOptionOnly
    else {
      throw GlobalHotKeyError.inactiveRightOptionMonitor
    }

    do {
      try registerRightOption(configuration)
    } catch {
      rightOptionMonitor?.invalidate(notifyRelease: false)
      rightOptionMonitor = nil
      registeredConfiguration = nil
      throw error
    }
  }

  private func registerRightOption(_ configuration: HotKeyConfiguration) throws {
    let newMonitor: RightOptionEventMonitor
    do {
      newMonitor = try RightOptionEventMonitor(
        onPress: { [weak self] in self?.handlePress() },
        onRelease: { [weak self] in self?.handleRelease() },
        onFailure: { [weak self] message in self?.rightOptionMonitorFailed(message) }
      )
    } catch {
      throw error
    }

    if let hotKeyRef {
      let status = UnregisterEventHotKey(hotKeyRef)
      guard status == noErr else {
        newMonitor.invalidate()
        throw GlobalHotKeyError.registrationFailed(status)
      }
      self.hotKeyRef = nil
    }
    rightOptionMonitor?.invalidate()
    rightOptionMonitor = newMonitor
    registeredConfiguration = configuration
  }

  private func handlePress() {
    guard !isSuspended else { return }
    onPress?()
  }

  private func handleRelease() {
    guard !isSuspended else { return }
    onRelease?()
  }

  private func rightOptionMonitorFailed(_ message: String) {
    let failedMonitor = rightOptionMonitor
    rightOptionMonitor = nil
    registeredConfiguration = nil
    failedMonitor?.invalidate(notifyRelease: false)
    onFailure?(message)
  }

  private func registerCarbonHotKey(_ configuration: HotKeyConfiguration) throws {
    guard configuration.isValidCustomChord else {
      throw GlobalHotKeyError.invalidConfiguration
    }

    if rightOptionMonitor != nil {
      var newReference: EventHotKeyRef?
      let status = registerReference(for: configuration, into: &newReference)
      guard status == noErr, let newReference else {
        throw GlobalHotKeyError.registrationFailed(status == noErr ? OSStatus(paramErr) : status)
      }

      rightOptionMonitor?.invalidate()
      rightOptionMonitor = nil
      hotKeyRef = newReference
      registeredConfiguration = configuration
      return
    }

    let previousConfiguration = registeredConfiguration
    if let hotKeyRef {
      let unregisterStatus = UnregisterEventHotKey(hotKeyRef)
      guard unregisterStatus == noErr else {
        throw GlobalHotKeyError.registrationFailed(unregisterStatus)
      }
      self.hotKeyRef = nil
    }

    var newReference: EventHotKeyRef?
    let status = registerReference(for: configuration, into: &newReference)
    guard status == noErr, let newReference else {
      if let previousConfiguration {
        var restoredReference: EventHotKeyRef?
        let restoreStatus = registerReference(
          for: previousConfiguration,
          into: &restoredReference
        )
        if restoreStatus == noErr, let restoredReference {
          hotKeyRef = restoredReference
          registeredConfiguration = previousConfiguration
        } else {
          registeredConfiguration = nil
        }
      }
      throw GlobalHotKeyError.registrationFailed(status == noErr ? OSStatus(paramErr) : status)
    }

    hotKeyRef = newReference
    registeredConfiguration = configuration
  }

  private func registerReference(
    for configuration: HotKeyConfiguration,
    into reference: inout EventHotKeyRef?
  ) -> OSStatus {
    let identifier = EventHotKeyID(signature: 0x464C_4F57, id: 1)  // FLOW
    return RegisterEventHotKey(
      configuration.keyCode,
      carbonModifiers(from: configuration.modifiers),
      identifier,
      GetApplicationEventTarget(),
      0,
      &reference
    )
  }

  private func carbonModifiers(from modifiers: HotKeyModifiers) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.command) { result |= UInt32(cmdKey) }
    if modifiers.contains(.option) { result |= UInt32(optionKey) }
    if modifiers.contains(.control) { result |= UInt32(controlKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    return result
  }

  private nonisolated(unsafe) static let eventCallback: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let identifierStatus = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &identifier
    )
    guard
      identifierStatus == noErr,
      identifier.signature == 0x464C_4F57,
      identifier.id == 1
    else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<GlobalHotKeyService>
      .fromOpaque(userData)
      .takeUnretainedValue()
    let kind = GetEventKind(event)

    if Thread.isMainThread {
      MainActor.assumeIsolated {
        if kind == UInt32(kEventHotKeyPressed) {
          service.handlePress()
        } else if kind == UInt32(kEventHotKeyReleased) {
          service.handleRelease()
        }
      }
    } else {
      Task { @MainActor in
        if kind == UInt32(kEventHotKeyPressed) {
          service.handlePress()
        } else if kind == UInt32(kEventHotKeyReleased) {
          service.handleRelease()
        }
      }
    }
    return noErr
  }
}
