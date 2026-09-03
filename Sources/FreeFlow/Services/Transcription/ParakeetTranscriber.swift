import FluidAudio
import Foundation

enum ParakeetTranscriberError: LocalizedError {
  case unsupportedPlatform
  case modelNotPrepared

  var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      "Parakeet requires an Apple Silicon Mac. Choose Whisper Small on Intel."
    case .modelNotPrepared:
      "Parakeet is not ready. Download it in FreeFlow Setup before dictating."
    }
  }
}

actor ParakeetTranscriber {
  private var manager: AsrManager?

  func modelExists() -> Bool {
    guard PlatformSupport.supportsParakeet else { return false }
    return AsrModels.modelsExist(
      at: AsrModels.defaultCacheDirectory(for: .v3),
      version: .v3
    )
  }

  func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
    guard PlatformSupport.supportsParakeet else {
      throw ParakeetTranscriberError.unsupportedPlatform
    }
    guard manager == nil else { return }

    let models = try await AsrModels.downloadAndLoad(
      version: .v3,
      progressHandler: { snapshot in
        progress(snapshot.fractionCompleted)
      }
    )
    manager = AsrManager(models: models)
  }

  func transcribe(
    _ audioURL: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    guard modelExists() else {
      throw ParakeetTranscriberError.modelNotPrepared
    }
    try await prepare(progress: progress)
    guard let manager else {
      throw ParakeetTranscriberError.unsupportedPlatform
    }

    let layers = await manager.decoderLayerCount
    var decoderState = TdtDecoderState.make(decoderLayers: layers)
    let result = try await manager.transcribe(
      audioURL,
      decoderState: &decoderState,
      language: .english
    )
    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func deleteModel() async throws {
    if let manager {
      await manager.cleanup()
    }
    manager = nil

    let directory = AsrModels.defaultCacheDirectory(for: .v3)
    guard directory.lastPathComponent.lowercased().contains("parakeet") else { return }
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
}
