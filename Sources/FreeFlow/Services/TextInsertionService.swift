import AppKit
import ApplicationServices
import Foundation
import FreeFlowCore

struct TextInsertionTarget {
  fileprivate let application: NSRunningApplication
  fileprivate let focusedElement: AXUIElement?
  fileprivate let prefersPaste: Bool

  fileprivate var processIdentifier: pid_t { application.processIdentifier }
}

private struct ClipboardItemSnapshot {
  let representations: [(type: NSPasteboard.PasteboardType, data: Data)]

  func makePasteboardItem() -> NSPasteboardItem? {
    let item = NSPasteboardItem()
    for representation in representations {
      guard item.setData(representation.data, forType: representation.type) else { return nil }
    }
    return item
  }
}

private struct ClipboardSnapshot {
  let items: [ClipboardItemSnapshot]

  static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot? {
    guard let pasteboardItems = pasteboard.pasteboardItems else {
      let hasDeclaredTypes = !(pasteboard.types?.isEmpty ?? true)
      return hasDeclaredTypes ? nil : ClipboardSnapshot(items: [])
    }

    var snapshots: [ClipboardItemSnapshot] = []
    for item in pasteboardItems {
      var representations: [(type: NSPasteboard.PasteboardType, data: Data)] = []
      for type in item.types {
        guard let data = item.data(forType: type) else { return nil }
        representations.append((type: type, data: data))
      }
      snapshots.append(ClipboardItemSnapshot(representations: representations))
    }
    return ClipboardSnapshot(items: snapshots)
  }

  func restore(to pasteboard: NSPasteboard) -> Bool {
    var restoredItems: [NSPasteboardItem] = []
    for item in items {
      guard let restoredItem = item.makePasteboardItem() else { return false }
      restoredItems.append(restoredItem)
    }

    pasteboard.clearContents()
    guard !restoredItems.isEmpty else { return true }
    return pasteboard.writeObjects(restoredItems)
  }
}

enum TextInsertionError: LocalizedError {
  case clipboardWriteFailed

  var errorDescription: String? {
    "FreeFlow could not copy the transcript to the clipboard."
  }
}

@MainActor
final class TextInsertionService {
  private static let pasteDeliveryDelay: Duration = .milliseconds(120)

  var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

  func captureTarget() -> TextInsertionTarget? {
    guard
      let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return nil }

    return TextInsertionTarget(
      application: application,
      focusedElement: focusedElement(for: application.processIdentifier),
      prefersPaste: Self.prefersPaste(
        bundleIdentifier: application.bundleIdentifier,
        applicationName: application.localizedName
      )
    )
  }

  @discardableResult
  func requestAccessibilityPermission() -> Bool {
    let promptKey = "AXTrustedCheckOptionPrompt"
    return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  func insert(
    _ text: String,
    into target: TextInsertionTarget?,
    mode: InsertionMode
  ) async throws -> InsertionResult {
    if mode == .clipboardOnly {
      try writeToClipboard(text)
      return .clipboard
    }

    guard let target, !target.application.isTerminated else {
      try writeToClipboard(text)
      return .clipboard
    }

    if AXIsProcessTrusted(), !target.prefersPaste,
      let focusedElement = target.focusedElement,
      setSelectedText(text, focusedElement: focusedElement)
    {
      return .accessibility
    }

    guard
      AXIsProcessTrusted(),
      await activateAndWaitForTarget(target),
      let focusedElement = target.focusedElement,
      restoreFocus(to: focusedElement, targetPID: target.processIdentifier),
      NSWorkspace.shared.frontmostApplication?.isEqual(target.application) == true
    else {
      try writeToClipboard(text)
      return .clipboard
    }

    return try await pasteWithTemporaryClipboard(text, into: target)
  }

  private func focusedElement(for targetPID: pid_t) -> AXUIElement? {
    guard AXIsProcessTrusted() else { return nil }

    let application = AXUIElementCreateApplication(targetPID)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        application,
        kAXFocusedUIElementAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private func setSelectedText(_ text: String, focusedElement: AXUIElement) -> Bool {
    AXUIElementSetAttributeValue(
      focusedElement,
      kAXSelectedTextAttribute as CFString,
      text as CFTypeRef
    ) == .success
  }

  private func restoreFocus(to capturedElement: AXUIElement, targetPID: pid_t) -> Bool {
    // Some Electron fields report success without restoring the visible focus.
    // Verify the exact element captured when dictation began before pasting.
    _ = AXUIElementSetAttributeValue(
      capturedElement,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )

    guard let currentElement = focusedElement(for: targetPID) else { return false }
    return CFEqual(currentElement, capturedElement)
  }

  private func activateAndWaitForTarget(_ target: TextInsertionTarget) async -> Bool {
    guard !target.application.isTerminated, target.application.activate(options: []) else {
      return false
    }

    for _ in 0..<12 {
      if NSWorkspace.shared.frontmostApplication?.isEqual(target.application) == true {
        return true
      }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return false
  }

  private func writeToClipboard(_ text: String) throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      throw TextInsertionError.clipboardWriteFailed
    }
  }

  private func pasteWithTemporaryClipboard(
    _ text: String,
    into target: TextInsertionTarget
  ) async throws -> InsertionResult {
    let pasteboard = NSPasteboard.general
    let snapshot = ClipboardSnapshot.capture(from: pasteboard)
    let selectionBeforePaste = target.focusedElement.flatMap(selectedTextRange)

    try writeToClipboard(text)
    let transcriptChangeCount = pasteboard.changeCount

    guard targetRemainsStable(target), postPasteShortcut(to: target.processIdentifier) else {
      return .clipboard
    }

    try? await Task.sleep(for: Self.pasteDeliveryDelay)

    let targetIsStable = !Task.isCancelled && targetRemainsStable(target)
    let pasteboardIsUnchanged =
      pasteboard.changeCount == transcriptChangeCount
      && pasteboard.string(forType: .string) == text
    let insertionIsConfirmed =
      targetIsStable
      && pasteWasConfirmed(
        text,
        selectionBeforePaste: selectionBeforePaste,
        target: target
      )
    let completionAction = ClipboardRestorationPolicy.completionAction(
      snapshotIsComplete: snapshot != nil,
      targetIsStable: targetIsStable,
      pasteboardIsUnchanged: pasteboardIsUnchanged,
      insertionIsConfirmed: insertionIsConfirmed
    )
    if completionAction == .preserveExternalClipboard {
      return .clipboard
    }
    guard completionAction == .restoreSnapshot, let snapshot else {
      try writeToClipboard(text)
      return .clipboard
    }

    guard snapshot.restore(to: pasteboard) else {
      try writeToClipboard(text)
      return .clipboard
    }
    return .paste
  }

  private func pasteWasConfirmed(
    _ text: String,
    selectionBeforePaste: CFRange?,
    target: TextInsertionTarget
  ) -> Bool {
    guard
      let selectionBeforePaste,
      selectionBeforePaste.location != kCFNotFound,
      let focusedElement = target.focusedElement,
      let selectionAfterPaste = selectedTextRange(focusedElement),
      selectionAfterPaste.length == 0
    else { return false }

    return selectionAfterPaste.location
      == selectionBeforePaste.location + (text as NSString).length
  }

  private func selectedTextRange(_ element: AXUIElement) -> CFRange? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
  }

  private func targetRemainsStable(_ target: TextInsertionTarget) -> Bool {
    guard
      !target.application.isTerminated,
      NSWorkspace.shared.frontmostApplication?.isEqual(target.application) == true,
      let capturedElement = target.focusedElement,
      let currentElement = focusedElement(for: target.processIdentifier)
    else { return false }
    return CFEqual(currentElement, capturedElement)
  }

  private func postPasteShortcut(to targetPID: pid_t) -> Bool {
    guard
      let source = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 9,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 9,
        keyDown: false
      )
    else { return false }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.postToPid(targetPID)
    keyUp.postToPid(targetPID)
    return true
  }

  private static func prefersPaste(bundleIdentifier: String?, applicationName: String?) -> Bool {
    let identity = [bundleIdentifier, applicationName]
      .compactMap { $0?.lowercased() }
      .joined(separator: " ")
    return [
      "chatgpt", "chrome", "chromium", "com.openai.codex", "cursor", "electron",
      "visual studio code", "vscode",
    ]
    .contains { identity.contains($0) }
  }
}
