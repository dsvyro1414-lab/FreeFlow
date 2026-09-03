import FreeFlowCloud
import FreeFlowCore

extension TranscriptionProvider {
  var cloudAPIProvider: CloudAPIProvider? {
    switch self {
    case .parakeet, .whisper: nil
    case .openAI: .openAI
    case .xAI: .xAI
    case .groq: .groq
    }
  }
}
