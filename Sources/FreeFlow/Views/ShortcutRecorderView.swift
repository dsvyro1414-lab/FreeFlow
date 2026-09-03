import AppKit
import FreeFlowCore
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
  @Binding var configuration: HotKeyConfiguration
  var onRecordingChanged: (Bool) -> Void = { _ in }

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton()
    button.onChange = { configuration = $0 }
    button.onRecordingChanged = onRecordingChanged
    button.update(configuration)
    return button
  }

  func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
    button.onChange = { configuration = $0 }
    button.onRecordingChanged = onRecordingChanged
    button.update(configuration)
  }
}

final class ShortcutRecorderButton: NSButton {
  var onChange: ((HotKeyConfiguration) -> Void)?
  var onRecordingChanged: ((Bool) -> Void)?
  private var configuration = HotKeyConfiguration.defaultValue
  private var isRecordingShortcut = false

  override var acceptsFirstResponder: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    bezelStyle = .rounded
    target = self
    action = #selector(beginRecording)
    setButtonType(.momentaryPushIn)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(_ configuration: HotKeyConfiguration) {
    self.configuration = configuration
    if !isRecordingShortcut {
      title = configuration.displayString
    }
  }

  @objc private func beginRecording() {
    isRecordingShortcut = true
    onRecordingChanged?(true)
    title = "Type shortcut…"
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    guard isRecordingShortcut else {
      super.keyDown(with: event)
      return
    }
    if event.keyCode == 53 {
      finishRecording(with: nil)
      return
    }
    guard !Self.modifierKeyCodes.contains(event.keyCode) else { return }

    let modifiers = Self.hotKeyModifiers(from: event.modifierFlags)
    guard !modifiers.isEmpty else {
      NSSound.beep()
      return
    }

    let value = HotKeyConfiguration(
      keyCode: UInt32(event.keyCode),
      modifiers: modifiers,
      keyLabel: Self.keyLabel(for: event)
    )
    finishRecording(with: value)
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if isRecordingShortcut {
      isRecordingShortcut = false
      onRecordingChanged?(false)
      title = configuration.displayString
    }
    return result
  }

  private func finishRecording(with value: HotKeyConfiguration?) {
    isRecordingShortcut = false
    onRecordingChanged?(false)
    if let value {
      configuration = value
      onChange?(value)
    }
    title = configuration.displayString
    window?.makeFirstResponder(nil)
  }

  private static let modifierKeyCodes: Set<UInt16> = [
    54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  ]

  private static func hotKeyModifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
    let flags = flags.intersection(.deviceIndependentFlagsMask)
    var result: HotKeyModifiers = []
    if flags.contains(.command) { result.insert(.command) }
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.shift) { result.insert(.shift) }
    return result
  }

  private static func keyLabel(for event: NSEvent) -> String {
    switch event.keyCode {
    case 36: return "Return"
    case 48: return "Tab"
    case 49: return "Space"
    case 51: return "Delete"
    case 117: return "Forward Delete"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default:
      let value = event.charactersIgnoringModifiers?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
      return value?.isEmpty == false ? value! : "Key \(event.keyCode)"
    }
  }
}
