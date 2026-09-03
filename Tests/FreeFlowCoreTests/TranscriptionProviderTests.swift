import XCTest

@testable import FreeFlowCore

final class TranscriptionProviderTests: XCTestCase {
  func testLegacyRawValuesRemainStable() {
    XCTAssertEqual(TranscriptionProvider.parakeet.rawValue, "parakeet")
    XCTAssertEqual(TranscriptionProvider.whisper.rawValue, "whisper")
    XCTAssertEqual(TranscriptionProvider.openAI.rawValue, "openAI")
  }

  func testOnlyDownloadedModelProvidersAreLocal() {
    XCTAssertTrue(TranscriptionProvider.parakeet.isLocal)
    XCTAssertTrue(TranscriptionProvider.whisper.isLocal)
    XCTAssertFalse(TranscriptionProvider.openAI.isLocal)
    XCTAssertFalse(TranscriptionProvider.xAI.isLocal)
    XCTAssertFalse(TranscriptionProvider.groq.isLocal)
  }
}
