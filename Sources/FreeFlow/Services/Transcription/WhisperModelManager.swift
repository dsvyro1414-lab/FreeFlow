import CryptoKit
import Foundation

enum WhisperModelError: LocalizedError {
  case invalidResponse
  case checksumMismatch
  case modelNotPrepared

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "The Whisper model download failed."
    case .checksumMismatch:
      "The downloaded Whisper model did not pass its integrity check."
    case .modelNotPrepared:
      "Whisper is not ready. Download it in FreeFlow Setup before dictating."
    }
  }
}

actor WhisperModelManager {
  func modelExists() -> Bool {
    FileManager.default.fileExists(atPath: modelURL.path)
  }

  func ensureModel(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
    if modelExists() { return modelURL }

    progress(0)
    let (temporaryURL, response) = try await URLSession.shared.download(
      from: AppConstants.whisperModelURL
    )
    guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
      throw WhisperModelError.invalidResponse
    }
    progress(0.9)

    let checksum = try sha256(of: temporaryURL)
    guard checksum == AppConstants.whisperModelSHA256 else {
      throw WhisperModelError.checksumMismatch
    }

    try FileManager.default.createDirectory(
      at: modelsDirectory,
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: modelURL.path) {
      try FileManager.default.removeItem(at: modelURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: modelURL)
    progress(1)
    return modelURL
  }

  func existingModelURL() throws -> URL {
    guard modelExists() else { throw WhisperModelError.modelNotPrepared }
    return modelURL
  }

  func deleteModel() throws {
    guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
    try FileManager.default.removeItem(at: modelURL)
  }

  private var modelsDirectory: URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return
      base
      .appendingPathComponent(AppConstants.appName, isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
  }

  private var modelURL: URL {
    modelsDirectory.appendingPathComponent(AppConstants.whisperModelFilename)
  }

  private func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
