import AVFoundation
import Foundation
import FreeFlowCore

enum AudioRecorderError: LocalizedError {
  case microphoneNotRequested
  case microphoneDenied
  case inputUnavailable
  case notRecording
  case recordingTooShort
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .microphoneNotRequested:
      "Allow Microphone access in FreeFlow Setup before dictating."
    case .microphoneDenied:
      "Microphone access is required to dictate."
    case .inputUnavailable:
      "No microphone input is available."
    case .notRecording:
      "FreeFlow is not currently recording."
    case .recordingTooShort:
      "Hold the shortcut a little longer before releasing."
    case .writeFailed(let message):
      "Could not save the recording: \(message)"
    }
  }
}

private final class AudioFileSink: @unchecked Sendable {
  private let file: AVAudioFile
  private let lock = NSLock()
  private(set) var error: Error?

  init(file: AVAudioFile) {
    self.file = file
  }

  func write(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard error == nil else { return }
    do {
      try file.write(from: buffer)
    } catch {
      self.error = error
    }
  }

  func snapshotError() -> Error? {
    lock.lock()
    defer { lock.unlock() }
    return error
  }
}

@MainActor
final class AudioRecorder {
  private let engine = AVAudioEngine()
  private var sink: AudioFileSink?
  private var currentURL: URL?
  private var startedAt: Date?
  private var tapInstalled = false

  var isRecording: Bool { engine.isRunning && currentURL != nil }
  var hasActiveSession: Bool { currentURL != nil }

  var permissionState: MicrophonePermissionState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined: .notRequested
    case .authorized: .granted
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }

  func requestPermission() async -> MicrophonePermissionState {
    guard permissionState == .notRequested else { return permissionState }

    _ = await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
    return permissionState
  }

  func start(levelHandler: @escaping @MainActor @Sendable (Float) -> Void) async throws {
    switch permissionState {
    case .granted:
      break
    case .notRequested:
      throw AudioRecorderError.microphoneNotRequested
    case .denied, .restricted:
      throw AudioRecorderError.microphoneDenied
    }
    guard !isRecording else { return }

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw AudioRecorderError.inputUnavailable
    }

    let fileURL = OwnedRecordingFile.makeURL()
    let file: AVAudioFile
    do {
      file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
    } catch {
      _ = try? OwnedRecordingFile.removeIfOwned(fileURL)
      throw error
    }
    let sink = AudioFileSink(file: file)

    input.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: format,
      block: Self.makeTapBlock(sink: sink, levelHandler: levelHandler)
    )
    tapInstalled = true

    do {
      engine.prepare()
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      tapInstalled = false
      engine.stop()
      _ = try? OwnedRecordingFile.removeIfOwned(fileURL)
      throw error
    }

    self.sink = sink
    currentURL = fileURL
    startedAt = Date()
  }

  func stop() throws -> URL {
    guard let currentURL else { throw AudioRecorderError.notRecording }

    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    engine.stop()

    let writeError = sink?.snapshotError()
    let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    sink = nil
    self.currentURL = nil
    startedAt = nil

    if let writeError {
      _ = try? OwnedRecordingFile.removeIfOwned(currentURL)
      throw AudioRecorderError.writeFailed(writeError.localizedDescription)
    }
    guard duration >= 0.25 else {
      _ = try? OwnedRecordingFile.removeIfOwned(currentURL)
      throw AudioRecorderError.recordingTooShort
    }
    return currentURL
  }

  private nonisolated static func makeTapBlock(
    sink: AudioFileSink,
    levelHandler: @escaping @MainActor @Sendable (Float) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, _ in
      sink.write(buffer)
      let level = normalizedLevel(from: buffer)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          levelHandler(level)
        }
      }
    }
  }

  private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
    guard
      let channels = buffer.floatChannelData,
      buffer.frameLength > 0
    else { return 0 }

    let samples = channels[0]
    let count = Int(buffer.frameLength)
    var sum: Float = 0
    for index in 0..<count {
      let value = samples[index]
      sum += value * value
    }
    let rms = sqrt(sum / Float(count))
    let decibels = 20 * log10(max(rms, 0.000_01))
    return min(max((decibels + 55) / 55, 0), 1)
  }
}
