import FreeFlowCore

extension TranscriptionProvider {
  var title: String {
    switch self {
    case .parakeet: "Parakeet"
    case .whisper: "Whisper Small"
    case .openAI: "OpenAI API"
    case .xAI: "xAI (Grok) Speech-to-Text"
    case .groq: "Groq Whisper API"
    }
  }

  var subtitle: String {
    switch self {
    case .parakeet: "Recommended · local · Apple Silicon"
    case .whisper: "Light · local · Intel and Apple Silicon"
    case .openAI: "Cloud · bring your own API key"
    case .xAI: "Cloud · xAI API key"
    case .groq: "Cloud · fast Whisper · Groq API key"
    }
  }
}

extension InsertionMode {
  var title: String {
    switch self {
    case .activeApplication: "Insert into active app"
    case .clipboardOnly: "Copy to clipboard"
    }
  }
}

extension HotKeyConfiguration {
  var displayString: String {
    var result = ""
    if modifiers.contains(.control) { result += "⌃" }
    if modifiers.contains(.option) { result += "⌥" }
    if modifiers.contains(.shift) { result += "⇧" }
    if modifiers.contains(.command) { result += "⌘" }
    return result + keyLabel
  }
}
