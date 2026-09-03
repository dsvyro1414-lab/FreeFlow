public enum HoldShortcutTransition: Equatable, Sendable {
  case pressed
  case released
}

public struct HoldShortcutState: Sendable {
  private enum Phase: Sendable {
    case idle
    case pressed
    case suppressedUntilRelease
  }

  private var phase: Phase

  public init(isPhysicallyPressed: Bool = false) {
    phase = isPhysicallyPressed ? .suppressedUntilRelease : .idle
  }

  public mutating func update(isPressed newValue: Bool) -> HoldShortcutTransition? {
    switch (phase, newValue) {
    case (.idle, true):
      phase = .pressed
      return .pressed
    case (.pressed, false):
      phase = .idle
      return .released
    case (.suppressedUntilRelease, false):
      phase = .idle
      return nil
    default:
      return nil
    }
  }

  public mutating func reset(suppressUntilRelease: Bool = false) -> HoldShortcutTransition? {
    let transition: HoldShortcutTransition? = phase == .pressed ? .released : nil
    phase = suppressUntilRelease ? .suppressedUntilRelease : .idle
    return transition
  }
}
