enum ModelStatus: Equatable {
  case notDownloaded
  case downloading(Double)
  case ready
  case failed(String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}
