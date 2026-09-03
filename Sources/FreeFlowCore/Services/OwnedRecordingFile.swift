import Foundation

public enum OwnedRecordingFile {
  private static let filenamePrefix = "FreeFlow-"

  public static func makeURL(
    in temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) -> URL {
    temporaryDirectory
      .appendingPathComponent("\(filenamePrefix)\(UUID().uuidString)")
      .appendingPathExtension("wav")
  }

  public static func isOwned(
    _ url: URL,
    in temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) -> Bool {
    let standardized = url.standardizedFileURL
    let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
    let temporary = temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
    guard
      parent.path == temporary.path,
      standardized.pathExtension.lowercased() == "wav"
    else { return false }

    let stem = standardized.deletingPathExtension().lastPathComponent
    guard stem.hasPrefix(filenamePrefix) else { return false }
    return UUID(uuidString: String(stem.dropFirst(filenamePrefix.count))) != nil
  }

  @discardableResult
  public static func removeIfOwned(
    _ url: URL,
    in temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    fileManager: FileManager = .default
  ) throws -> Bool {
    guard isOwned(url, in: temporaryDirectory) else { return false }

    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
    try fileManager.removeItem(at: url)
    return true
  }

  @discardableResult
  public static func removeStaleFiles(
    olderThan age: TimeInterval,
    now: Date = Date(),
    in temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    fileManager: FileManager = .default
  ) throws -> Int {
    guard age >= 0 else { return 0 }

    let candidates = try fileManager.contentsOfDirectory(
      at: temporaryDirectory,
      includingPropertiesForKeys: [
        .contentModificationDateKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ],
      options: [.skipsSubdirectoryDescendants]
    )
    let cutoff = now.addingTimeInterval(-age)
    var removedCount = 0

    for candidate in candidates where isOwned(candidate, in: temporaryDirectory) {
      let values = try candidate.resourceValues(forKeys: [
        .contentModificationDateKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ])
      guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let modificationDate = values.contentModificationDate,
        modificationDate <= cutoff
      else { continue }

      try fileManager.removeItem(at: candidate)
      removedCount += 1
    }

    return removedCount
  }
}
