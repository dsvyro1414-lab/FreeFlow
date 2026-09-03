import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@main
struct FreeFlowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: model)
    } label: {
      Image(systemName: model.menuBarIcon)
        .accessibilityLabel("FreeFlow")
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(model: model)
    }
  }
}
