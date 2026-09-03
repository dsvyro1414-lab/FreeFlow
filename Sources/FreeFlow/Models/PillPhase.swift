enum PillPhase: Equatable {
  case hidden
  case recording
  case downloading(Double)
  case processing
  case success(InsertionResult)
  case failure(String)
}
