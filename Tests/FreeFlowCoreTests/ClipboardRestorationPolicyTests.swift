import XCTest

@testable import FreeFlowCore

final class ClipboardRestorationPolicyTests: XCTestCase {
  func testRestoresOnlyWhenEverySafetyConditionHolds() {
    XCTAssertEqual(
      ClipboardRestorationPolicy.completionAction(
        snapshotIsComplete: true,
        targetIsStable: true,
        pasteboardIsUnchanged: true,
        insertionIsConfirmed: true
      ),
      .restoreSnapshot
    )
  }

  func testKeepsTranscriptWhenSnapshotIsIncomplete() {
    XCTAssertEqual(
      ClipboardRestorationPolicy.completionAction(
        snapshotIsComplete: false,
        targetIsStable: true,
        pasteboardIsUnchanged: true,
        insertionIsConfirmed: true
      ),
      .keepTranscript
    )
  }

  func testKeepsTranscriptWhenTargetChanges() {
    XCTAssertEqual(
      ClipboardRestorationPolicy.completionAction(
        snapshotIsComplete: true,
        targetIsStable: false,
        pasteboardIsUnchanged: true,
        insertionIsConfirmed: true
      ),
      .keepTranscript
    )
  }

  func testPreservesExternalClipboardWhenPasteboardChanges() {
    XCTAssertEqual(
      ClipboardRestorationPolicy.completionAction(
        snapshotIsComplete: true,
        targetIsStable: true,
        pasteboardIsUnchanged: false,
        insertionIsConfirmed: true
      ),
      .preserveExternalClipboard
    )
  }

  func testKeepsTranscriptWhenPasteCannotBeConfirmed() {
    XCTAssertEqual(
      ClipboardRestorationPolicy.completionAction(
        snapshotIsComplete: true,
        targetIsStable: true,
        pasteboardIsUnchanged: true,
        insertionIsConfirmed: false
      ),
      .keepTranscript
    )
  }
}
