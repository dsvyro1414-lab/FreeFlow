import XCTest

@testable import FreeFlowCore

final class SetupReadinessTests: XCTestCase {
  func testFullExperienceRequiresEveryFullExperienceGate() {
    let readiness = SetupReadiness(
      experience: .full,
      modelReady: false,
      microphoneGranted: false,
      transcriptionTestPassed: false,
      accessibilityGranted: false,
      customShortcutConfigured: false
    )

    XCTAssertEqual(
      readiness.blockers,
      [.model, .microphone, .transcriptionTest, .accessibility]
    )
    XCTAssertFalse(readiness.canComplete)
  }

  func testFullExperienceDoesNotRequireCustomShortcut() {
    let readiness = SetupReadiness(
      experience: .full,
      modelReady: true,
      microphoneGranted: true,
      transcriptionTestPassed: true,
      accessibilityGranted: true,
      customShortcutConfigured: false
    )

    XCTAssertTrue(readiness.canComplete)
  }

  func testFewerPermissionsRequiresCustomChordButNotAccessibility() {
    let blocked = SetupReadiness(
      experience: .fewerPermissions,
      modelReady: true,
      microphoneGranted: true,
      transcriptionTestPassed: true,
      accessibilityGranted: false,
      customShortcutConfigured: false
    )
    XCTAssertEqual(blocked.blockers, [.customShortcut])

    let ready = SetupReadiness(
      experience: .fewerPermissions,
      modelReady: true,
      microphoneGranted: true,
      transcriptionTestPassed: true,
      accessibilityGranted: false,
      customShortcutConfigured: true
    )
    XCTAssertTrue(ready.canComplete)
  }

  func testTranscriptionTestRemainsRequiredAfterPermissionGrant() {
    let readiness = SetupReadiness(
      experience: .fewerPermissions,
      modelReady: true,
      microphoneGranted: true,
      transcriptionTestPassed: false,
      accessibilityGranted: false,
      customShortcutConfigured: true
    )

    XCTAssertEqual(readiness.blockers, [.transcriptionTest])
  }
}
