enum OpenAITranscriptionModel: String, CaseIterable, Identifiable {
  case mini = "gpt-4o-mini-transcribe"
  case quality = "gpt-4o-transcribe"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .mini: "Fast"
    case .quality: "Quality"
    }
  }
}
