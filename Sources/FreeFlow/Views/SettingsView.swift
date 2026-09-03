import FreeFlowCloud
import FreeFlowCore
import SwiftUI

struct SettingsView: View {
  private enum Tab: Hashable {
    case general
    case models
    case cloud
  }

  @ObservedObject var model: AppModel
  @ObservedObject private var preferences: PreferencesStore
  @State private var selectedTab: Tab = .general

  init(model: AppModel) {
    self.model = model
    preferences = model.preferences
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      generalTab
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(Tab.general)
      modelsTab
        .tabItem { Label("Models", systemImage: "cpu") }
        .tag(Tab.models)
      apiTab
        .tabItem { Label("Cloud", systemImage: "cloud") }
        .tag(Tab.cloud)
    }
    .frame(width: 570, height: 500)
    .padding(20)
    .onAppear { model.refreshSetupState() }
  }

  private var generalTab: some View {
    Form {
      Section("Setup") {
        LabeledContent("Status") {
          Label(
            model.hasCompletedSetup ? "Complete" : "Not complete",
            systemImage: model.hasCompletedSetup
              ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
          )
          .foregroundStyle(model.hasCompletedSetup ? .green : .orange)
        }
        Button(model.hasCompletedSetup ? "Open Setup Again…" : "Finish Setup…") {
          model.showSetup()
        }
      }

      Section("Shortcut") {
        LabeledContent("Hold to dictate") {
          HStack {
            ShortcutRecorderView(
              configuration: $preferences.hotKey,
              onRecordingChanged: model.setShortcutRecordingActive
            )
            .frame(width: 150, height: 28)
            Button("Use Right Option") {
              preferences.hotKey = .rightOption
            }
            .disabled(preferences.hotKey.isRightOptionOnly)
          }
        }
      }

      Section("Output") {
        Picker("After transcription", selection: $preferences.insertionMode) {
          ForEach(InsertionMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        Toggle("Remove acoustic fillers (um, uh, erm, hmm)", isOn: $preferences.removeFillers)
      }

      Section("Permissions") {
        LabeledContent("Accessibility") {
          if model.isAccessibilityGranted {
            HStack {
              Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
              if !model.isSelectedHotKeyActive {
                Button("Retry") { model.retryHotKeyRegistration() }
              }
            }
          } else {
            HStack {
              Button("Enable") { model.requestAccessibilityPermission() }
              Button("Open Settings") { model.openAccessibilitySettings() }
            }
          }
        }
        LabeledContent("Microphone") {
          switch model.microphonePermission {
          case .notRequested:
            Button("Allow") { model.requestMicrophonePermission() }
          case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          case .denied, .restricted:
            HStack {
              Label(model.microphonePermission.title, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
              Button("Open Settings") { model.openMicrophoneSettings() }
            }
          }
        }

        Text(
          "Accessibility enables Right Option and active-field insertion; FreeFlow does not read typed text. Custom chords and clipboard-only output need only Microphone. FreeFlow never requests Screen Recording, Full Disk Access, or Input Monitoring."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Text(
          "Some Chrome and Electron fields use a temporary clipboard paste. FreeFlow never overwrites a newer clipboard value; Copy last transcript remains available."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var modelsTab: some View {
    Form {
      Section("Transcription engine") {
        Picker("Engine", selection: $preferences.provider) {
          ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
            Text(provider.title)
              .tag(provider)
              .disabled(provider == .parakeet && !PlatformSupport.supportsParakeet)
          }
        }
        .pickerStyle(.radioGroup)

        if let provider = preferences.provider.cloudAPIProvider {
          LabeledContent("API key") {
            HStack {
              if model.isAPIKeyConfigured(for: provider) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                  .foregroundStyle(.green)
              } else {
                Label("Not configured", systemImage: "exclamationmark.circle.fill")
                  .foregroundStyle(.orange)
                Button("Open Cloud") {
                  selectedTab = .cloud
                }
              }
            }
          }
        }
      }

      Section("Local models") {
        ModelRowView(
          title: "Parakeet TDT 0.6B v3",
          subtitle: "Recommended · high-quality English · ~600 MB",
          status: model.parakeetStatus,
          isAvailable: PlatformSupport.supportsParakeet,
          download: { model.downloadModel(.parakeet) },
          remove: { model.deleteModel(.parakeet) }
        )
        ModelRowView(
          title: "Whisper Small English Q5",
          subtitle: "Compatibility · Intel + Apple Silicon · 181 MiB",
          status: model.whisperStatus,
          isAvailable: true,
          download: { model.downloadModel(.whisper) },
          remove: { model.deleteModel(.whisper) }
        )
      }
    }
    .formStyle(.grouped)
  }

  private var apiTab: some View {
    Form {
      Section("Bring your own keys") {
        CloudCredentialEditor(
          provider: .openAI,
          isConfigured: model.isAPIKeyConfigured(for: .openAI),
          save: { try model.saveAPIKey($0, for: .openAI) },
          delete: { try model.deleteAPIKey(for: .openAI) }
        )

        CloudCredentialEditor(
          provider: .xAI,
          isConfigured: model.isAPIKeyConfigured(for: .xAI),
          save: { try model.saveAPIKey($0, for: .xAI) },
          delete: { try model.deleteAPIKey(for: .xAI) }
        )

        CloudCredentialEditor(
          provider: .groq,
          isConfigured: model.isAPIKeyConfigured(for: .groq),
          save: { try model.saveAPIKey($0, for: .groq) },
          delete: { try model.deleteAPIKey(for: .groq) }
        )
      }

      Section("Cloud models") {
        Picker("OpenAI", selection: $preferences.openAIModel) {
          ForEach(OpenAITranscriptionModel.allCases) { model in
            Text("\(model.title) — \(model.rawValue)").tag(model)
          }
        }

        LabeledContent("xAI (Grok)") {
          Text("Speech-to-Text")
            .foregroundStyle(.secondary)
        }

        Picker("Groq", selection: $preferences.groqModel) {
          ForEach(GroqTranscriptionModel.allCases) { model in
            Text("\(model.title) — \(model.rawValue)").tag(model)
          }
        }
      }

      Text(
        "Keys stay in macOS Keychain. Audio is sent only to the cloud engine selected in Models; local engines make no API request."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
  }
}
