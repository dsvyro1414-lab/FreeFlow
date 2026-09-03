public enum CloudAPIProvider: String, CaseIterable, Identifiable, Sendable {
  case openAI
  case xAI
  case groq

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .openAI: "OpenAI"
    case .xAI: "xAI (Grok)"
    case .groq: "Groq"
    }
  }

  public var keychainAccount: String {
    switch self {
    case .openAI: "openai-api-key"
    case .xAI: "xai-api-key"
    case .groq: "groq-api-key"
    }
  }
}
