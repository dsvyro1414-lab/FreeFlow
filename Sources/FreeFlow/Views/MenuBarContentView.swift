import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    if model.hasCompletedSetup {
      Text("Hold \(model.preferences.hotKey.displayString) to dictate")
        .foregroundStyle(.secondary)
    } else {
      Text("Finish Setup before your first dictation")
        .foregroundStyle(.secondary)
      Button("Finish Setup…") {
        model.showSetup()
      }
    }

    if model.hasCompletedSetup,
      model.preferences.hotKey.isRightOptionOnly,
      !model.isSelectedHotKeyActive
    {
      if model.isAccessibilityGranted {
        Button("Retry Right Option") {
          model.retryHotKeyRegistration()
        }
      } else {
        Button("Enable Right Option & Insertion…") {
          model.requestAccessibilityPermission()
        }
      }
    }

    if model.hasCompletedSetup {
      Divider()
      Label(
        "Microphone: \(model.microphonePermission.title)",
        systemImage: model.microphonePermission == .granted
          ? "checkmark.circle" : "exclamationmark.circle"
      )
      if model.preferences.insertionMode == .activeApplication {
        Label(
          "Accessibility: \(model.isAccessibilityGranted ? "Granted" : "Needed")",
          systemImage: model.isAccessibilityGranted
            ? "checkmark.circle" : "exclamationmark.circle"
        )
      }
    }

    if !model.lastTranscript.isEmpty {
      Divider()
      Button("Copy last transcript") {
        model.copyLastTranscript()
      }
    }

    if let error = model.lastError {
      Divider()
      Text(String(error.prefix(48)))
        .foregroundStyle(.red)
    }

    Divider()
    Button("Open Setup…") {
      model.showSetup()
    }
    SettingsLink {
      Label("Settings…", systemImage: "gearshape")
    }
    Button("Quit FreeFlow") {
      NSApplication.shared.terminate(nil)
    }
  }
}
