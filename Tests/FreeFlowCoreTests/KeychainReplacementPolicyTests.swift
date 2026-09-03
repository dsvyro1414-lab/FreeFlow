import XCTest

@testable import FreeFlowCore

final class KeychainReplacementPolicyTests: XCTestCase {
  private let success: Int32 = 0
  private let itemNotFound: Int32 = -25_300
  private let duplicateItem: Int32 = -25_299

  func testExistingItemCompletesWithUpdate() {
    XCTAssertEqual(
      KeychainReplacementPolicy.afterUpdate(
        status: success,
        success: success,
        itemNotFound: itemNotFound
      ),
      .complete
    )
  }

  func testMissingItemAdvancesToAddWithoutDelete() {
    XCTAssertEqual(
      KeychainReplacementPolicy.afterUpdate(
        status: itemNotFound,
        success: success,
        itemNotFound: itemNotFound
      ),
      .add
    )
  }

  func testConcurrentAddRaceRetriesUpdate() {
    XCTAssertEqual(
      KeychainReplacementPolicy.afterAdd(
        status: duplicateItem,
        success: success,
        duplicateItem: duplicateItem
      ),
      .retryUpdate
    )
  }

  func testUnexpectedStatusesFailClosed() {
    XCTAssertEqual(
      KeychainReplacementPolicy.afterUpdate(
        status: -1,
        success: success,
        itemNotFound: itemNotFound
      ),
      .fail(-1)
    )
    XCTAssertEqual(
      KeychainReplacementPolicy.afterAdd(
        status: -2,
        success: success,
        duplicateItem: duplicateItem
      ),
      .fail(-2)
    )
  }
}
