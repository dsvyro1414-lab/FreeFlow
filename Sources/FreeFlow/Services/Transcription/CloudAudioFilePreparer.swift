import AVFoundation
import Foundation
import FreeFlowCore

enum CloudAudioFilePreparerError: LocalizedError {
  case invalidOutputFormat

  var errorDescription: String? {
    switch self {
    case .invalidOutputFormat:
      "Could not prepare the recording for cloud transcription."
    }
  }
}

actor CloudAudioFilePreparer {
  func prepare(_ sourceURL: URL) throws -> URL {
    try Task.checkCancellation()
    let samples = try AudioSampleLoader.mono16kSamples(from: sourceURL)
    guard
      samples.count <= Int(UInt32.max),
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
      ),
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let outputSamples = outputBuffer.int16ChannelData?[0]
    else {
      throw CloudAudioFilePreparerError.invalidOutputFormat
    }

    outputBuffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() {
      if index.isMultiple(of: 65_536) {
        try Task.checkCancellation()
      }
      guard sample.isFinite else {
        outputSamples[index] = 0
        continue
      }
      let clamped = min(max(sample, -1), 1)
      outputSamples[index] = Int16((clamped * Float(Int16.max)).rounded())
    }

    let outputURL = OwnedRecordingFile.makeURL()
    var shouldKeepOutput = false
    defer {
      if !shouldKeepOutput {
        _ = try? OwnedRecordingFile.removeIfOwned(outputURL)
      }
    }

    let file = try AVAudioFile(
      forWriting: outputURL,
      settings: outputFormat.settings,
      commonFormat: .pcmFormatInt16,
      interleaved: true
    )
    try file.write(from: outputBuffer)
    try Task.checkCancellation()
    shouldKeepOutput = true
    return outputURL
  }
}
