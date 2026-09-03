import FreeFlowCore
import SwiftUI

struct SetupView: View {
  private enum Page: Int, CaseIterable {
    case welcome
    case model
    case microphone
    case output
    case ready

    var title: String {
      switch self {
      case .welcome: "Choose"
      case .model: "Model"
      case .microphone: "Test"
      case .output: "Output"
      case .ready: "Ready"
      }
    }
  }

  @ObservedObject var model: AppModel
  @ObservedObject private var preferences: PreferencesStore
  @State private var page: Page = .welcome

  init(model: AppModel) {
    self.model = model
    preferences = model.preferences
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        pageContent
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, 32)
          .padding(.vertical, 24)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.refreshSetupState() }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 32, weight: .semibold))
        .foregroundStyle(.tint)

      VStack(alignment: .leading, spacing: 2) {
        Text("FreeFlow Setup")
          .font(.title2.weight(.semibold))
        Text("Private dictation, prepared before the first recording")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 7) {
        ForEach(Page.allCases, id: \.rawValue) { item in
          VStack(spacing: 5) {
            Circle()
              .fill(
                item.rawValue <= page.rawValue ? Color.accentColor : Color.secondary.opacity(0.2)
              )
              .frame(width: 8, height: 8)
            Text(item.title)
              .font(.caption2)
              .foregroundStyle(item == page ? .primary : .secondary)
          }
          .frame(width: 40)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Setup step \(page.rawValue + 1) of \(Page.allCases.count): \(page.title)")
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 20)
  }

  @ViewBuilder
  private var pageContent: some View {
    switch page {
    case .welcome:
      welcomePage
    case .model:
      modelPage
    case .microphone:
      microphonePage
    case .output:
      outputPage
    case .ready:
      readyPage
    }
  }

  private var welcomePage: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageTitle(
        "How should FreeFlow work?",
        subtitle: "Both options transcribe locally and require no account or subscription."
      )

      experienceCard(
        .full,
        title: "Full experience",
        subtitle: "Hold Right Option and insert text directly into the active field.",
        details: "Microphone + Accessibility",
        symbol: "wand.and.stars",
        recommended: true
      )

      experienceCard(
        .minimal,
        title: "Use fewer permissions",
        subtitle: "Choose a normal key chord and receive every transcript on the clipboard.",
        details: "Microphone only",
        symbol: "lock.shield",
        recommended: false
      )

      privacyNote(
        "Local mode keeps recordings and transcripts on this Mac. Cloud APIs are optional and are never used by Setup."
      )
    }
  }

  private var modelPage: some View {
    VStack(alignment: .leading, spacing: 24) {
      pageTitle(
        "Prepare local transcription",
        subtitle: "FreeFlow downloads the model now, before it accepts a dictation."
      )

      HStack(spacing: 18) {
        Image(systemName: model.recommendedLocalProvider == .parakeet ? "apple.logo" : "cpu")
          .font(.system(size: 30))
          .frame(width: 48, height: 48)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 4) {
          Text(
            model.recommendedLocalProvider == .parakeet
              ? "Parakeet TDT 0.6B v3" : "Whisper Small English Q5"
          )
          .font(.headline)
          Text(
            model.recommendedLocalProvider == .parakeet
              ? "Recommended for Apple Silicon · about 600 MB"
              : "Compatibility model for Intel · 181 MiB"
          )
          .foregroundStyle(.secondary)
        }

        Spacer()
        modelStatusControl
      }
      .padding(18)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

      privacyNote(
        "The model is stored in your user Library. Audio stays local when Parakeet or Whisper is selected."
      )
    }
  }

  @ViewBuilder
  private var modelStatusControl: some View {
    switch model.selectedLocalModelStatus {
    case .notDownloaded:
      Button("Download Model") {
        model.downloadModel(model.recommendedLocalProvider)
      }
      .buttonStyle(.borderedProminent)
    case .downloading(let progress):
      VStack(alignment: .trailing, spacing: 6) {
        ProgressView(value: progress)
          .frame(width: 130)
        Text("\(Int(progress * 100))%")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    case .ready:
      Label("Ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed(let message):
      VStack(alignment: .trailing, spacing: 5) {
        Button("Retry Download") {
          model.downloadModel(model.recommendedLocalProvider)
        }
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
          .frame(maxWidth: 190, alignment: .trailing)
      }
    }
  }

  private var microphonePage: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageTitle(
        "Allow the microphone, then test it",
        subtitle:
          "The test records a short phrase and transcribes it locally. It does not insert or copy anything."
      )

      permissionRow(
        symbol: "mic.fill",
        title: "Microphone",
        explanation: "Used only while you hold your shortcut or run this test."
      ) {
        microphoneControl
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Transcription test")
          .font(.headline)
        Text("Say a short English phrase, for example: “FreeFlow is ready.”")
          .foregroundStyle(.secondary)

        setupTestControl
      }
      .padding(18)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
  }

  @ViewBuilder
  private var microphoneControl: some View {
    switch model.microphonePermission {
    case .notRequested:
      Button("Allow Microphone") { model.requestMicrophonePermission() }
        .buttonStyle(.borderedProminent)
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

  @ViewBuilder
  private var setupTestControl: some View {
    switch model.setupTestState {
    case .idle:
      Button("Start Test Recording") { model.startSetupTest() }
        .disabled(model.microphonePermission != .granted || !model.selectedLocalModelStatus.isReady)
    case .recording:
      HStack(spacing: 10) {
        Circle()
          .fill(.red)
          .frame(width: 9, height: 9)
          .accessibilityHidden(true)
        Text("Recording…")
        Button("Stop and Transcribe") { model.finishSetupTest() }
          .buttonStyle(.borderedProminent)
      }
    case .processing:
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("Transcribing locally…")
      }
    case .success(let transcript):
      VStack(alignment: .leading, spacing: 8) {
        Label("Test passed", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("“\(transcript)”")
          .textSelection(.enabled)
        Button("Run Again") { model.startSetupTest() }
          .buttonStyle(.link)
      }
    case .failure(let message):
      VStack(alignment: .leading, spacing: 8) {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Button("Try Again") { model.startSetupTest() }
      }
    }
  }

  @ViewBuilder
  private var outputPage: some View {
    switch model.selectedSetupExperience {
    case .full:
      fullOutputPage
    case .minimal:
      minimalOutputPage
    }
  }

  private var fullOutputPage: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageTitle(
        "Enable Right Option and direct insertion",
        subtitle:
          "One Accessibility permission lets FreeFlow observe Right Option and place the finished transcript in the active field."
      )

      permissionRow(
        symbol: "accessibility",
        title: "Accessibility",
        explanation: "FreeFlow does not read the text you type or inspect document contents."
      ) {
        if model.isAccessibilityGranted {
          Label("Granted", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          HStack {
            Button("Enable Accessibility") { model.requestAccessibilityPermission() }
              .buttonStyle(.borderedProminent)
            Button("Open Settings") { model.openAccessibilitySettings() }
          }
        }
      }

      if !model.isAccessibilityGranted {
        Text(
          "Already On in System Settings? That row may belong to an older source build. Remove it, then add the exact FreeFlow copy you launched (normally ~/Applications/FreeFlow.app)."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      privacyNote(
        "FreeFlow first attempts direct Accessibility insertion. Chrome and Electron may require a temporary clipboard paste; the previous clipboard is restored only when it is safe to do so."
      )
    }
    .onAppear { model.observeAccessibilityPermission() }
  }

  private var minimalOutputPage: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageTitle(
        "Choose a shortcut",
        subtitle:
          "Clipboard-only mode avoids Accessibility. A normal chord is required because Right Option needs Accessibility monitoring."
      )

      HStack(spacing: 18) {
        Image(systemName: "keyboard")
          .font(.system(size: 27))
          .frame(width: 48, height: 48)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 4) {
          Text("Hold to dictate")
            .font(.headline)
          Text("Click the control, then press a chord such as Control–Space.")
            .foregroundStyle(.secondary)
        }
        Spacer()
        ShortcutRecorderView(
          configuration: $preferences.hotKey,
          onRecordingChanged: model.setShortcutRecordingActive
        )
        .frame(width: 160, height: 30)
      }
      .padding(18)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

      if !preferences.hotKey.isValidCustomChord {
        Label(
          "Choose a chord with at least one modifier.", systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
      } else {
        Label(
          "\(preferences.hotKey.displayString) will copy each transcript.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      }

      privacyNote(
        "Clipboard-only mode leaves the transcript on the clipboard until you replace it.")
    }
  }

  private var readyPage: some View {
    VStack(alignment: .leading, spacing: 24) {
      pageTitle(
        "You’re ready to dictate",
        subtitle: model.selectedSetupExperience == .full
          ? "FreeFlow will live in the menu bar and listen only while you hold Right Option."
          : "FreeFlow will live in the menu bar and listen only while you hold your shortcut."
      )

      VStack(alignment: .leading, spacing: 16) {
        readyRow(
          "1",
          model.selectedSetupExperience == .full
            ? "Hold Right Option" : "Hold \(preferences.hotKey.displayString)")
        readyRow("2", "Speak in English")
        readyRow(
          "3", model.selectedSetupExperience == .full ? "Release to insert" : "Release, then paste")
      }
      .padding(22)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))

      Text("You can reopen Setup or review permission status from the menu bar at any time.")
        .font(.callout)
        .foregroundStyle(.secondary)

      if let error = model.lastError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
      }
    }
  }

  private var footer: some View {
    HStack {
      Button("Back") {
        if let previous = Page(rawValue: page.rawValue - 1) {
          page = previous
        }
      }
      .disabled(
        page == .welcome || model.setupTestState == .recording
          || model.setupTestState == .processing)

      Spacer()

      if page == .ready {
        Button("Finish Setup") { model.completeSetup() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!model.setupReadiness.canComplete)
      } else {
        Button("Continue") {
          if let next = Page(rawValue: page.rawValue + 1) {
            page = next
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canContinue)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 16)
  }

  private var canContinue: Bool {
    switch page {
    case .welcome:
      true
    case .model:
      model.selectedLocalModelStatus.isReady
    case .microphone:
      model.microphonePermission == .granted && model.setupTestState.hasPassed
    case .output:
      model.selectedSetupExperience == .full
        ? model.isAccessibilityGranted
        : preferences.hotKey.isValidCustomChord
    case .ready:
      model.setupReadiness.canComplete
    }
  }

  private func experienceCard(
    _ experience: SetupExperience,
    title: String,
    subtitle: String,
    details: String,
    symbol: String,
    recommended: Bool
  ) -> some View {
    Button {
      model.selectSetupExperience(experience)
    } label: {
      HStack(spacing: 16) {
        Image(systemName: symbol)
          .font(.system(size: 25))
          .foregroundStyle(.tint)
          .frame(width: 44, height: 44)
          .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 8) {
            Text(title)
              .font(.headline)
            if recommended {
              Text("RECOMMENDED")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
          }
          Text(subtitle)
            .foregroundStyle(.secondary)
          Text(details)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: selected(experience) ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(selected(experience) ? Color.accentColor : Color.secondary.opacity(0.45))
      }
      .padding(16)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected(experience)
        ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 14)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(
          selected(experience) ? Color.accentColor : Color.secondary.opacity(0.16),
          lineWidth: selected(experience) ? 2 : 1)
    }
  }

  private func selected(_ experience: SetupExperience) -> Bool {
    model.selectedSetupExperience == experience
  }

  private func pageTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(.title, design: .rounded, weight: .semibold))
      Text(subtitle)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func permissionRow<Control: View>(
    symbol: String,
    title: String,
    explanation: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(spacing: 16) {
      Image(systemName: symbol)
        .font(.system(size: 25))
        .frame(width: 46, height: 46)
        .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(explanation)
          .foregroundStyle(.secondary)
      }
      Spacer()
      control()
    }
    .padding(18)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
  }

  private func privacyNote(_ text: String) -> some View {
    Label {
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "hand.raised.fill")
        .foregroundStyle(.secondary)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
  }

  private func readyRow(_ number: String, _ text: String) -> some View {
    HStack(spacing: 14) {
      Text(number)
        .font(.headline.monospacedDigit())
        .frame(width: 30, height: 30)
        .background(Color.accentColor, in: Circle())
        .foregroundStyle(.white)
      Text(text)
        .font(.title3.weight(.medium))
    }
  }
}
