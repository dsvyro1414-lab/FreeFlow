public enum ClipboardCompletionAction: Equatable, Sendable {
  case restoreSnapshot
  case keepTranscript
  case preserveExternalClipboard
}

public enum ClipboardRestorationPolicy {
  public static func completionAction(
    snapshotIsComplete: Bool,
    targetIsStable: Bool,
    pasteboardIsUnchanged: Bool,
    insertionIsConfirmed: Bool
  ) -> ClipboardCompletionAction {
    if !pasteboardIsUnchanged {
      return .preserveExternalClipboard
    }
    if snapshotIsComplete && targetIsStable && pasteboardIsUnchanged && insertionIsConfirmed {
      return .restoreSnapshot
    }
    return .keepTranscript
  }
}
