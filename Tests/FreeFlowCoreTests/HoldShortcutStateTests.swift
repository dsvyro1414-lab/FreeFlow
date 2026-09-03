import Foundation
import XCTest

@testable import FreeFlowCore

final class HoldShortcutStateTests: XCTestCase {
  func testEmitsExactlyOneTransitionForEachPhysicalChange() {
    var state = HoldShortcutState()

    XCTAssertEqual(state.update(isPressed: true), .pressed)
    XCTAssertNil(state.update(isPressed: true))
    XCTAssertEqual(state.update(isPressed: false), .released)
    XCTAssertNil(state.update(isPressed: false))
  }

  func testResetReleasesOnlyAnActiveHold() {
    var state = HoldShortcutState()

    XCTAssertNil(state.reset())
    XCTAssertEqual(state.update(isPressed: true), .pressed)
    XCTAssertEqual(state.reset(), .released)
    XCTAssertNil(state.reset())
  }

  func testStartupWhileHeldWaitsForAFullNewPress() {
    var state = HoldShortcutState(isPhysicallyPressed: true)

    XCTAssertNil(state.update(isPressed: true))
    XCTAssertNil(state.update(isPressed: false))
    XCTAssertEqual(state.update(isPressed: true), .pressed)
  }

  func testResetWhileHeldSuppressesEventsUntilPhysicalRelease() {
    var state = HoldShortcutState()

    XCTAssertEqual(state.update(isPressed: true), .pressed)
    XCTAssertEqual(state.reset(suppressUntilRelease: true), .released)
    XCTAssertNil(state.update(isPressed: true))
    XCTAssertNil(state.update(isPressed: false))
    XCTAssertEqual(state.update(isPressed: true), .pressed)
  }

  func testRightOptionIsTheSimpleDefault() throws {
    let configuration = HotKeyConfiguration.defaultValue

    XCTAssertEqual(configuration, .rightOption)
    XCTAssertEqual(configuration.keyCode, 61)
    XCTAssertTrue(configuration.modifiers.isEmpty)
    XCTAssertTrue(configuration.isRightOptionOnly)
    XCTAssertFalse(configuration.isValidCustomChord)

    let encoded = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(HotKeyConfiguration.self, from: encoded)
    XCTAssertEqual(decoded, configuration)
  }

  func testLetterChordIsNotClassifiedAsRightOption() {
    let chord = HotKeyConfiguration(keyCode: 2, modifiers: [.option], keyLabel: "D")

    XCTAssertFalse(chord.isRightOptionOnly)
    XCTAssertTrue(chord.isValidCustomChord)
  }

  func testCustomChordRejectsBareAndModifierOnlyKeys() {
    let bareKey = HotKeyConfiguration(keyCode: 2, modifiers: [], keyLabel: "D")
    let modifierOnly = HotKeyConfiguration(
      keyCode: 58,
      modifiers: [.option],
      keyLabel: "Option"
    )

    XCTAssertFalse(bareKey.isValidCustomChord)
    XCTAssertFalse(modifierOnly.isValidCustomChord)
  }
}
