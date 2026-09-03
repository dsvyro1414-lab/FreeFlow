import AppKit
import SwiftUI

@MainActor
final class PillWindowController {
  private let panel: NSPanel

  init(model: PillPresentationModel) {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 136, height: 46),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let hostingView = NSHostingView(
      rootView: RecordingPillView(model: model)
        .background(Color.clear)
    )
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    hostingView.layer?.isOpaque = false
    panel.contentView = hostingView
  }

  func activeScreen() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return
      NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  func show(on preferredScreen: NSScreen? = nil) {
    position(on: preferredScreen ?? activeScreen())
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }

  private func position(on preferredScreen: NSScreen?) {
    let screen =
      preferredScreen.flatMap { preferred in
        NSScreen.screens.first { $0 === preferred }
      } ?? activeScreen()
    guard let screen else { return }

    let frame = panel.frame
    let visible = screen.visibleFrame
    let origin = NSPoint(
      x: visible.midX - frame.width / 2,
      y: visible.minY + 22
    )
    panel.setFrameOrigin(origin)
  }
}
