public enum KeychainReplacementStep: Equatable, Sendable {
  case complete
  case add
  case retryUpdate
  case fail(Int32)
}

public enum KeychainReplacementPolicy {
  public static func afterUpdate(
    status: Int32,
    success: Int32,
    itemNotFound: Int32
  ) -> KeychainReplacementStep {
    if status == success { return .complete }
    if status == itemNotFound { return .add }
    return .fail(status)
  }

  public static func afterAdd(
    status: Int32,
    success: Int32,
    duplicateItem: Int32
  ) -> KeychainReplacementStep {
    if status == success { return .complete }
    if status == duplicateItem { return .retryUpdate }
    return .fail(status)
  }
}
