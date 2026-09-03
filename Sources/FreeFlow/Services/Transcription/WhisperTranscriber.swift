import Foundation
import whisper

enum WhisperTranscriberError: LocalizedError {
  case modelLoadFailed
  case inferenceFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .modelLoadFailed:
      "Whisper could not load its local model."
    case .inferenceFailed(let code):
      "Whisper transcription failed with code \(code)."
    }
  }
}

actor WhisperTranscriber {
  private let modelManager: WhisperModelManager
  private var context: OpaquePointer?
  private var loadedModelPath: String?

  init(modelManager: WhisperModelManager) {
    self.modelManager = modelManager
  }

  func modelExists() async -> Bool {
    await modelManager.modelExists()
  }

  func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
    let url = try await modelManager.ensureModel(progress: progress)
    try loadModelIfNeeded(at: url)
  }

  func transcribe(
    _ audioURL: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    let modelURL = try await modelManager.existingModelURL()
    try loadModelIfNeeded(at: modelURL)
    guard let context else { throw WhisperTranscriberError.modelLoadFailed }

    let samples = try AudioSampleLoader.mono16kSamples(from: audioURL)
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
    params.translate = false
    params.no_context = true
    params.no_timestamps = true
    params.single_segment = false
    params.print_special = false
    params.print_progress = false
    params.print_realtime = false
    params.print_timestamps = false
    params.suppress_blank = true
    params.temperature = 0
    params.greedy.best_of = 1

    let result = samples.withUnsafeBufferPointer { buffer in
      whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
    }
    guard result == 0 else {
      throw WhisperTranscriberError.inferenceFailed(result)
    }

    let segmentCount = whisper_full_n_segments(context)
    var transcript = ""
    for index in 0..<segmentCount {
      if let text = whisper_full_get_segment_text(context, index) {
        transcript += String(cString: text)
      }
    }
    return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func deleteModel() async throws {
    unload()
    try await modelManager.deleteModel()
  }

  private func loadModelIfNeeded(at url: URL) throws {
    if loadedModelPath == url.path, context != nil { return }
    unload()

    var parameters = whisper_context_default_params()
    parameters.use_gpu = true
    parameters.flash_attn = true
    let loaded = url.path.withCString {
      whisper_init_from_file_with_params($0, parameters)
    }
    guard let loaded else { throw WhisperTranscriberError.modelLoadFailed }
    context = loaded
    loadedModelPath = url.path
  }

  private func unload() {
    if let context {
      whisper_free(context)
    }
    context = nil
    loadedModelPath = nil
  }
}
