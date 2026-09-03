import Foundation

enum AppConstants {
  static let appName = "FreeFlow"
  static let bundleIdentifier = "com.dsvyro.freeflow"
  static let whisperModelFilename = "ggml-small.en-q5_1.bin"
  static let whisperModelSHA256 = "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30"
  static let whisperModelURL = URL(
    string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin"
  )!
}
