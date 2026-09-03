import Combine

@MainActor
final class PillPresentationModel: ObservableObject {
  @Published var phase: PillPhase = .hidden
  @Published var audioLevel: Float = 0

  var label: String {
    switch phase {
    case .hidden:
      ""
    case .recording:
      "Listening"
    case .downloading(let progress):
      progress > 0 ? "Downloading \(Int(progress * 100))%" : "Downloading model"
    case .processing:
      "Transcribing"
    case .success(let result):
      result == .clipboard ? "Copied" : "Inserted"
    case .failure:
      "Failed"
    }
  }
}
