enum GroqTranscriptionModel: String, CaseIterable, Identifiable {
  case turbo = "whisper-large-v3-turbo"
  case quality = "whisper-large-v3"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .turbo: "Fast"
    case .quality: "Quality"
    }
  }
}
