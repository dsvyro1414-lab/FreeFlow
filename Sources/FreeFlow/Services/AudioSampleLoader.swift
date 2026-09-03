import AVFoundation
import Foundation

private final class AudioConverterInputSource: @unchecked Sendable {
  private let buffer: AVAudioPCMBuffer
  private let lock = NSLock()
  private var supplied = false

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }

    guard !supplied else {
      status.pointee = .endOfStream
      return nil
    }
    supplied = true
    status.pointee = .haveData
    return buffer
  }
}

enum AudioSampleLoaderError: LocalizedError {
  case invalidFormat
  case conversionFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidFormat:
      "The recorded audio format is invalid."
    case .conversionFailed(let message):
      "Audio conversion failed: \(message)"
    }
  }
}

enum AudioSampleLoader {
  static func mono16kSamples(from url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let inputFormat = file.processingFormat
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      ),
      let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
      file.length <= AVAudioFramePosition(UInt32.max),
      let inputBuffer = AVAudioPCMBuffer(
        pcmFormat: inputFormat,
        frameCapacity: AVAudioFrameCount(file.length)
      )
    else {
      throw AudioSampleLoaderError.invalidFormat
    }

    try file.read(into: inputBuffer)

    let ratio = outputFormat.sampleRate / inputFormat.sampleRate
    let outputCapacity = AVAudioFrameCount(
      ceil(Double(inputBuffer.frameLength) * ratio) + 32
    )
    guard
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: outputCapacity
      )
    else {
      throw AudioSampleLoaderError.invalidFormat
    }

    let inputSource = AudioConverterInputSource(buffer: inputBuffer)
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, status in
      inputSource.next(status: status)
    }

    if status == .error {
      throw AudioSampleLoaderError.conversionFailed(
        conversionError?.localizedDescription ?? "Unknown converter error"
      )
    }
    guard let data = outputBuffer.floatChannelData?[0] else {
      throw AudioSampleLoaderError.invalidFormat
    }
    return Array(UnsafeBufferPointer(start: data, count: Int(outputBuffer.frameLength)))
  }
}
