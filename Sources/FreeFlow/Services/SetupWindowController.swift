import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
  private weak var model: AppModel?

  init(model: AppModel) {
    self.model = model
    let rootView = SetupView(model: model)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "FreeFlow Setup"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 620, height: 480))
    window.contentMinSize = NSSize(width: 520, height: 400)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.animationBehavior = .documentWindow
    let restoredFrame = window.setFrameUsingName("FreeFlowSetupWindow")
    _ = window.setFrameAutosaveName("FreeFlowSetupWindow")
    if !restoredFrame {
      window.center()
    }
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show() {
    guard let window else { return }
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    model?.setupDidDisappear()
  }
}
