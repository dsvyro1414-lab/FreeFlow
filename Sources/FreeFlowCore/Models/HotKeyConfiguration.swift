public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public static let command = HotKeyModifiers(rawValue: 1 << 0)
  public static let option = HotKeyModifiers(rawValue: 1 << 1)
  public static let control = HotKeyModifiers(rawValue: 1 << 2)
  public static let shift = HotKeyModifiers(rawValue: 1 << 3)
}

public struct HotKeyConfiguration: Codable, Equatable, Sendable {
  public static let rightOptionKeyCode: UInt32 = 61

  public let keyCode: UInt32
  public let modifiers: HotKeyModifiers
  public let keyLabel: String

  public init(keyCode: UInt32, modifiers: HotKeyModifiers, keyLabel: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.keyLabel = keyLabel
  }

  public static let rightOption = HotKeyConfiguration(
    keyCode: rightOptionKeyCode,
    modifiers: [],
    keyLabel: "Right Option"
  )

  public static let defaultValue = rightOption

  public var isRightOptionOnly: Bool {
    keyCode == Self.rightOptionKeyCode && modifiers.isEmpty
  }

  public var isValidCustomChord: Bool {
    !isRightOptionOnly
      && !modifiers.isEmpty
      && !Self.modifierKeyCodes.contains(keyCode)
  }

  private static let modifierKeyCodes: Set<UInt32> = [
    54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  ]
}
