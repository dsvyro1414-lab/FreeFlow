public enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
  case parakeet
  case whisper
  case openAI
  case xAI = "xai"
  case groq

  public var isLocal: Bool {
    switch self {
    case .parakeet, .whisper:
      true
    case .openAI, .xAI, .groq:
      false
    }
  }
}
