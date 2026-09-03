public struct SetupReadiness: Equatable, Sendable {
  public enum Experience: Equatable, Sendable {
    case full
    case fewerPermissions
  }

  public enum Blocker: Equatable, Sendable {
    case model
    case microphone
    case transcriptionTest
    case accessibility
    case customShortcut
  }

  public let experience: Experience
  public let modelReady: Bool
  public let microphoneGranted: Bool
  public let transcriptionTestPassed: Bool
  public let accessibilityGranted: Bool
  public let customShortcutConfigured: Bool

  public init(
    experience: Experience,
    modelReady: Bool,
    microphoneGranted: Bool,
    transcriptionTestPassed: Bool,
    accessibilityGranted: Bool,
    customShortcutConfigured: Bool
  ) {
    self.experience = experience
    self.modelReady = modelReady
    self.microphoneGranted = microphoneGranted
    self.transcriptionTestPassed = transcriptionTestPassed
    self.accessibilityGranted = accessibilityGranted
    self.customShortcutConfigured = customShortcutConfigured
  }

  public var blockers: [Blocker] {
    var result: [Blocker] = []
    if !modelReady { result.append(.model) }
    if !microphoneGranted { result.append(.microphone) }
    if !transcriptionTestPassed { result.append(.transcriptionTest) }

    switch experience {
    case .full:
      if !accessibilityGranted { result.append(.accessibility) }
    case .fewerPermissions:
      if !customShortcutConfigured { result.append(.customShortcut) }
    }
    return result
  }

  public var canComplete: Bool { blockers.isEmpty }
}
