import Foundation
import XCTest

@testable import FreeFlowCore

final class OwnedRecordingFileTests: XCTestCase {
  func testRecognizesOnlyExactOwnedFilenameInTemporaryDirectory() {
    let temporary = URL(fileURLWithPath: "/tmp/freeflow-owned-recording-tests", isDirectory: true)
    let uuid = UUID(uuidString: "5D1BD488-7FC9-4A76-A96F-7D6A39926C16")!

    XCTAssertTrue(
      OwnedRecordingFile.isOwned(
        temporary.appendingPathComponent("FreeFlow-\(uuid.uuidString).wav"),
        in: temporary
      )
    )
    XCTAssertFalse(
      OwnedRecordingFile.isOwned(
        temporary.appendingPathComponent("FreeFlow-not-a-uuid.wav"),
        in: temporary
      )
    )
    XCTAssertFalse(
      OwnedRecordingFile.isOwned(
        temporary.appendingPathComponent("FreeFlow-\(uuid.uuidString).mp3"),
        in: temporary
      )
    )
    XCTAssertFalse(
      OwnedRecordingFile.isOwned(
        URL(fileURLWithPath: "/tmp/FreeFlow-\(uuid.uuidString).wav"),
        in: temporary
      )
    )
  }

  func testRemovesOwnedRegularFile() throws {
    let fileManager = FileManager.default
    let temporary = fileManager.temporaryDirectory
      .appendingPathComponent("FreeFlowTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporary) }

    let recording = OwnedRecordingFile.makeURL(in: temporary)
    XCTAssertTrue(fileManager.createFile(atPath: recording.path, contents: Data("audio".utf8)))

    XCTAssertTrue(
      try OwnedRecordingFile.removeIfOwned(
        recording,
        in: temporary,
        fileManager: fileManager
      )
    )
    XCTAssertFalse(fileManager.fileExists(atPath: recording.path))
  }

  func testPreservesSymlinkWithOwnedLookingName() throws {
    let fileManager = FileManager.default
    let temporary = fileManager.temporaryDirectory
      .appendingPathComponent("FreeFlowTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporary) }

    let target = temporary.appendingPathComponent("unrelated.wav")
    XCTAssertTrue(fileManager.createFile(atPath: target.path, contents: Data("keep".utf8)))
    let recording = OwnedRecordingFile.makeURL(in: temporary)
    try fileManager.createSymbolicLink(at: recording, withDestinationURL: target)

    XCTAssertFalse(
      try OwnedRecordingFile.removeIfOwned(
        recording,
        in: temporary,
        fileManager: fileManager
      )
    )
    XCTAssertTrue(fileManager.fileExists(atPath: target.path))
  }

  func testRemovesOnlyStaleOwnedRegularFiles() throws {
    let fileManager = FileManager.default
    let temporary = fileManager.temporaryDirectory
      .appendingPathComponent("FreeFlowTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporary) }

    let now = Date(timeIntervalSince1970: 10_000)
    let staleDate = now.addingTimeInterval(-3_600)
    let freshDate = now.addingTimeInterval(-30)

    let staleRecording = OwnedRecordingFile.makeURL(in: temporary)
    XCTAssertTrue(fileManager.createFile(atPath: staleRecording.path, contents: Data("old".utf8)))
    try fileManager.setAttributes(
      [.modificationDate: staleDate],
      ofItemAtPath: staleRecording.path
    )

    let freshRecording = OwnedRecordingFile.makeURL(in: temporary)
    XCTAssertTrue(fileManager.createFile(atPath: freshRecording.path, contents: Data("new".utf8)))
    try fileManager.setAttributes(
      [.modificationDate: freshDate],
      ofItemAtPath: freshRecording.path
    )

    let unrelated = temporary.appendingPathComponent("recording.wav")
    XCTAssertTrue(fileManager.createFile(atPath: unrelated.path, contents: Data("keep".utf8)))
    try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: unrelated.path)

    let ownedDirectory = OwnedRecordingFile.makeURL(in: temporary)
    try fileManager.createDirectory(at: ownedDirectory, withIntermediateDirectories: false)
    try fileManager.setAttributes(
      [.modificationDate: staleDate],
      ofItemAtPath: ownedDirectory.path
    )

    let symlinkTarget = temporary.appendingPathComponent("symlink-target.wav")
    XCTAssertTrue(fileManager.createFile(atPath: symlinkTarget.path, contents: Data("keep".utf8)))
    try fileManager.setAttributes(
      [.modificationDate: staleDate],
      ofItemAtPath: symlinkTarget.path
    )
    let ownedSymlink = OwnedRecordingFile.makeURL(in: temporary)
    try fileManager.createSymbolicLink(at: ownedSymlink, withDestinationURL: symlinkTarget)

    XCTAssertEqual(
      try OwnedRecordingFile.removeStaleFiles(
        olderThan: 300,
        now: now,
        in: temporary,
        fileManager: fileManager
      ),
      1
    )
    XCTAssertFalse(fileManager.fileExists(atPath: staleRecording.path))
    XCTAssertTrue(fileManager.fileExists(atPath: freshRecording.path))
    XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path))
    XCTAssertTrue(fileManager.fileExists(atPath: ownedDirectory.path))
    XCTAssertTrue(fileManager.fileExists(atPath: symlinkTarget.path))
    XCTAssertTrue(fileManager.fileExists(atPath: ownedSymlink.path))
  }

  func testNegativeStaleAgeRemovesNothing() throws {
    let fileManager = FileManager.default
    let temporary = fileManager.temporaryDirectory
      .appendingPathComponent("FreeFlowTests-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporary) }

    let recording = OwnedRecordingFile.makeURL(in: temporary)
    XCTAssertTrue(fileManager.createFile(atPath: recording.path, contents: Data("keep".utf8)))

    XCTAssertEqual(
      try OwnedRecordingFile.removeStaleFiles(
        olderThan: -1,
        now: Date(),
        in: temporary,
        fileManager: fileManager
      ),
      0
    )
    XCTAssertTrue(fileManager.fileExists(atPath: recording.path))
  }
}
