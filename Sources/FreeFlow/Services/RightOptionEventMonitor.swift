import ApplicationServices
import CoreGraphics
import Foundation
import FreeFlowCore
import OSLog

enum RightOptionEventMonitorError: LocalizedError {
  case accessibilityPermissionRequired
  case eventTapUnavailable

  var errorDescription: String? {
    switch self {
    case .accessibilityPermissionRequired:
      "Right Option needs Accessibility access in macOS System Settings."
    case .eventTapUnavailable:
      "Right Option monitoring could not start. Check Accessibility permission and try again."
    }
  }
}

@MainActor
final class RightOptionEventMonitor {
  // Device-dependent modifier flags occupy the low bits of CGEventFlags.
  // Right Option is bit 6 (NX_DEVICERALTKEYMASK). The generic
  // `.maskAlternate` bit cannot distinguish a Right Option release while
  // Left Option is still held.
  private nonisolated static let leftOptionDeviceFlag: UInt64 = 1 << 5
  private nonisolated static let rightOptionDeviceFlag: UInt64 = 1 << 6

  private let onPress: @MainActor () -> Void
  private let onRelease: @MainActor () -> Void
  private let onFailure: @MainActor (String) -> Void
  private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "HotKey")
  private var state: HoldShortcutState
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isActive = true

  init(
    onPress: @escaping @MainActor () -> Void,
    onRelease: @escaping @MainActor () -> Void,
    onFailure: @escaping @MainActor (String) -> Void
  ) throws {
    self.onPress = onPress
    self.onRelease = onRelease
    self.onFailure = onFailure

    guard AXIsProcessTrusted() else {
      throw RightOptionEventMonitorError.accessibilityPermissionRequired
    }

    state = HoldShortcutState(isPhysicallyPressed: Self.isRightOptionPhysicallyPressed)
    let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: Self.eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      logger.error("Right Option event tap creation failed")
      throw RightOptionEventMonitorError.eventTapUnavailable
    }
    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else {
      logger.error("Right Option run loop source creation failed")
      CFMachPortInvalidate(eventTap)
      throw RightOptionEventMonitorError.eventTapUnavailable
    }
    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    guard CGEvent.tapIsEnabled(tap: eventTap) else {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
      self.runLoopSource = nil
      logger.error("Right Option event tap could not be enabled")
      throw RightOptionEventMonitorError.eventTapUnavailable
    }
  }

  func invalidate(notifyRelease: Bool = true) {
    guard isActive else { return }
    isActive = false

    if notifyRelease {
      forceRelease()
    } else {
      _ = state.reset()
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFRunLoopSourceInvalidate(runLoopSource)
      self.runLoopSource = nil
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
  }

  private func handle(isPressed: Bool) {
    guard isActive else { return }
    guard let transition = state.update(isPressed: isPressed) else { return }

    switch transition {
    case .pressed:
      onPress()
    case .released:
      onRelease()
    }
  }

  private func handleTapDisabled(isPhysicallyPressed: Bool) {
    guard isActive else { return }
    logger.warning("Right Option event tap was disabled; attempting to re-enable it")
    reset(suppressUntilRelease: isPhysicallyPressed)
    guard let eventTap else { return }

    CGEvent.tapEnable(tap: eventTap, enable: true)
    guard !CGEvent.tapIsEnabled(tap: eventTap) else { return }

    let message = RightOptionEventMonitorError.eventTapUnavailable.localizedDescription
    logger.error("\(message, privacy: .public)")
    onFailure(message)
  }

  private func forceRelease() {
    reset(suppressUntilRelease: false)
  }

  func suppressUntilPhysicalRelease() {
    guard isActive else { return }
    reset(suppressUntilRelease: Self.isRightOptionPhysicallyPressed)
  }

  private func reset(suppressUntilRelease: Bool) {
    guard state.reset(suppressUntilRelease: suppressUntilRelease) == .released else { return }
    onRelease()
  }

  private nonisolated static var isRightOptionPhysicallyPressed: Bool {
    CGEventSource.keyState(
      .hidSystemState,
      key: CGKeyCode(HotKeyConfiguration.rightOptionKeyCode)
    )
  }

  private nonisolated(unsafe) static let eventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let monitor = Unmanaged<RightOptionEventMonitor>
      .fromOpaque(userInfo)
      .takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      let isPhysicallyPressed = RightOptionEventMonitor.isRightOptionPhysicallyPressed
      dispatchToMainActor {
        monitor.handleTapDisabled(isPhysicallyPressed: isPhysicallyPressed)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == CGKeyCode(HotKeyConfiguration.rightOptionKeyCode) else {
      return Unmanaged.passUnretained(event)
    }

    let rawFlags = event.flags.rawValue
    let hasSideSpecificOptionState =
      (rawFlags & (leftOptionDeviceFlag | rightOptionDeviceFlag)) != 0
    let isPressed =
      hasSideSpecificOptionState
      ? (rawFlags & rightOptionDeviceFlag) != 0
      : RightOptionEventMonitor.isRightOptionPhysicallyPressed
    dispatchToMainActor {
      monitor.handle(isPressed: isPressed)
    }
    return Unmanaged.passUnretained(event)
  }

  private nonisolated static func dispatchToMainActor(
    _ operation: @escaping @MainActor @Sendable () -> Void
  ) {
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        operation()
      }
    }
  }
}
