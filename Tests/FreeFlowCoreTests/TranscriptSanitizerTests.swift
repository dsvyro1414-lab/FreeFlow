import XCTest

@testable import FreeFlowCore

final class TranscriptSanitizerTests: XCTestCase {
  func testRemovesLeadingEnglishFiller() {
    XCTAssertEqual(
      TranscriptSanitizer.removingAcousticFillers(from: "Um, this is FreeFlow."),
      "this is FreeFlow."
    )
  }

  func testRemovesFillerBetweenClauses() {
    XCTAssertEqual(
      TranscriptSanitizer.removingAcousticFillers(from: "I, uh, think this works."),
      "I think this works."
    )
  }

  func testDoesNotAlterWordsContainingFillerText() {
    XCTAssertEqual(
      TranscriptSanitizer.removingAcousticFillers(
        from: "The album documents an unusual summer."
      ),
      "The album documents an unusual summer."
    )
  }

  func testPreservesSemanticUhOh() {
    XCTAssertEqual(
      TranscriptSanitizer.removingAcousticFillers(from: "Uh-oh, that failed."),
      "Uh-oh, that failed."
    )
  }
}
