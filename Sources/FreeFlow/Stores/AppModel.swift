import AppKit
import Combine
import Foundation
import FreeFlowCloud
import FreeFlowCore

enum DictationWorkflowError: LocalizedError {
  case noSpeechDetected
  case recordingTimedOut

  var errorDescription: String? {
    switch self {
    case .noSpeechDetected:
      "No speech was detected."
    case .recordingTimedOut:
      "Recording stopped after five minutes for safety."
    }
  }
}

enum SetupTestState: Equatable {
  case idle
  case recording
  case processing
  case success(String)
  case failure(String)

  var hasPassed: Bool {
    if case .success = self { return true }
    return false
  }
}

@MainActor
final class AppModel: ObservableObject {
  private static let accessibilityRecoveryAttemptCount = 90
  private static let accessibilityRecoveryInterval: Duration = .seconds(1)

  private enum DictationState {
    case idle
    case starting(UUID)
    case recording(UUID)
    case finishing(UUID)
    case processing(UUID)

    var sessionID: UUID? {
      switch self {
      case .idle: nil
      case .starting(let id), .recording(let id), .finishing(let id), .processing(let id): id
      }
    }

    var isIdle: Bool {
      if case .idle = self { return true }
      return false
    }
  }

  private struct DictationConfiguration {
    let provider: TranscriptionProvider
    let openAIModel: OpenAITranscriptionModel
    let groqModel: GroqTranscriptionModel
    let insertionMode: InsertionMode
    let removeFillers: Bool
  }

  @Published private(set) var lastTranscript = ""
  @Published private(set) var lastError: String?
  @Published private(set) var parakeetStatus: ModelStatus = .notDownloaded
  @Published private(set) var whisperStatus: ModelStatus = .notDownloaded
  @Published private(set) var configuredCloudProviders: Set<CloudAPIProvider> = []
  @Published private(set) var microphonePermission: MicrophonePermissionState
  @Published private(set) var selectedSetupExperience: SetupExperience
  @Published private(set) var setupTestState: SetupTestState = .idle
  @Published private(set) var isSetupVisible = false
  @Published private(set) var isAccessibilityGranted = false

  let preferences: PreferencesStore
  let pillModel: PillPresentationModel

  private let audioRecorder = AudioRecorder()
  private let insertionService = TextInsertionService()
  private let parakeet = ParakeetTranscriber()
  private let whisperModelManager = WhisperModelManager()
  private let whisper: WhisperTranscriber
  private let cloudAudioFilePreparer = CloudAudioFilePreparer()
  private let cloudTranscriber = CloudTranscriber()
  private let pillWindow: PillWindowController
  private lazy var setupWindow = SetupWindowController(model: self)
  private var hotKeyService: GlobalHotKeyService?
  private var cancellables: Set<AnyCancellable> = []
  private var isHotKeyHeld = false
  private var capturedTarget: TextInsertionTarget?
  private var capturedScreen: NSScreen?
  private var dictationState: DictationState = .idle
  private var dictationTask: Task<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Bool, Never>?
  private var releaseTimeoutTask: Task<Void, Never>?
  private var modelTask: Task<Void, Never>?
  private var modelOperationID: UUID?
  private var modelStatusRefreshID: UUID?
  private var pendingHotKeyConfiguration: HotKeyConfiguration?
  private var hotKeyRegistrationError: String?
  private var pillDismissTask: Task<Void, Never>?
  private var pillDismissID: UUID?
  private var accessibilityRecoveryTask: Task<Void, Never>?
  private var accessibilityRecoveryID: UUID?
  private var setupTestTask: Task<Void, Never>?

  init() {
    let preferences = PreferencesStore()
    let pillModel = PillPresentationModel()
    let whisper = WhisperTranscriber(modelManager: whisperModelManager)

    self.preferences = preferences
    self.pillModel = pillModel
    self.whisper = whisper
    microphonePermission = audioRecorder.permissionState
    selectedSetupExperience = preferences.setupExperience
    pillWindow = PillWindowController(model: pillModel)
    refreshAccessibilityPermission()

    _ = try? OwnedRecordingFile.removeStaleFiles(olderThan: 24 * 60 * 60)

    if preferences.hasCompletedSetup {
      updateHotKeyRegistration(preferences.hotKey)
    }

    preferences.$hotKey
      .dropFirst()
      .sink { [weak self] configuration in
        guard self?.preferences.hasCompletedSetup == true else { return }
        self?.updateHotKeyRegistration(configuration)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in
        self?.applicationDidBecomeActive()
      }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
      .sink { [weak self] _ in
        self?.shutdownForTermination()
      }
      .store(in: &cancellables)

    let workspaceNotifications = NSWorkspace.shared.notificationCenter
    workspaceNotifications.publisher(for: NSWorkspace.willSleepNotification)
      .sink { [weak self] _ in
        self?.hotKeyService?.handleSystemInterruption()
      }
      .store(in: &cancellables)
    workspaceNotifications.publisher(for: NSWorkspace.didWakeNotification)
      .sink { [weak self] _ in
        self?.rearmHotKeyAfterSystemInterruption()
      }
      .store(in: &cancellables)
    workspaceNotifications.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
      .sink { [weak self] _ in
        self?.hotKeyService?.handleSystemInterruption()
      }
      .store(in: &cancellables)
    workspaceNotifications.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
      .sink { [weak self] _ in
        self?.rearmHotKeyAfterSystemInterruption()
      }
      .store(in: &cancellables)

    refreshModelStatuses()
    refreshAPIKeyConfiguration()

    if !preferences.hasCompletedSetup {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        self?.showSetup()
      }
    }
  }

  var menuBarIcon: String {
    switch pillModel.phase {
    case .recording: "waveform.circle.fill"
    case .downloading, .processing: "ellipsis.circle"
    case .failure: "exclamationmark.circle"
    default: "waveform.circle"
    }
  }

  var hasCompletedSetup: Bool {
    preferences.hasCompletedSetup
  }

  var recommendedLocalProvider: TranscriptionProvider {
    PlatformSupport.supportsParakeet ? .parakeet : .whisper
  }

  var selectedLocalModelStatus: ModelStatus {
    switch recommendedLocalProvider {
    case .parakeet: parakeetStatus
    case .whisper: whisperStatus
    case .openAI, .xAI, .groq: .notDownloaded
    }
  }

  var setupReadiness: SetupReadiness {
    SetupReadiness(
      experience: selectedSetupExperience == .full ? .full : .fewerPermissions,
      modelReady: selectedLocalModelStatus.isReady,
      microphoneGranted: microphonePermission == .granted,
      transcriptionTestPassed: setupTestState.hasPassed,
      accessibilityGranted: isAccessibilityGranted,
      customShortcutConfigured: preferences.hotKey.isValidCustomChord
    )
  }

  var isSelectedHotKeyActive: Bool {
    hotKeyService?.currentConfiguration == preferences.hotKey
  }

  func showSetup() {
    isSetupVisible = true
    hotKeyService?.setSuspended(true)
    refreshSetupState()
    setupWindow.show()
  }

  func dismissSetup() {
    setupWindow.close()
  }

  func setupDidDisappear() {
    cancelSetupTest()
    cancelAccessibilityRecovery()
    isSetupVisible = false
    hotKeyService?.setSuspended(false)
  }

  func refreshSetupState() {
    microphonePermission = audioRecorder.permissionState
    refreshAccessibilityPermission()
    refreshModelStatuses()
    refreshAPIKeyConfiguration()
  }

  func selectSetupExperience(_ experience: SetupExperience) {
    guard setupTestState != .recording, setupTestState != .processing else { return }
    selectedSetupExperience = experience
    setupTestState = .idle
  }

  func requestMicrophonePermission() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      microphonePermission = await audioRecorder.requestPermission()
      if microphonePermission != .granted {
        lastError = "Microphone access was not granted. You can change it in System Settings."
      } else {
        lastError = nil
      }
    }
  }

  func startSetupTest() {
    guard setupTestTask == nil, dictationState.isIdle, modelTask == nil else { return }
    refreshSetupState()
    guard selectedLocalModelStatus.isReady else {
      setupTestState = .failure("Download the local model first.")
      return
    }
    guard microphonePermission == .granted else {
      setupTestState = .failure("Allow Microphone access first.")
      return
    }

    setupTestTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { setupTestTask = nil }
      guard !Task.isCancelled else { return }
      do {
        try await audioRecorder.start { _ in }
        guard !Task.isCancelled else {
          if audioRecorder.hasActiveSession, let audioURL = try? audioRecorder.stop() {
            _ = try? OwnedRecordingFile.removeIfOwned(audioURL)
          }
          return
        }
        setupTestState = .recording
        lastError = nil
      } catch is CancellationError {
        setupTestState = .idle
      } catch {
        guard !Task.isCancelled else { return }
        setupTestState = .failure(error.localizedDescription)
      }
    }
  }

  func finishSetupTest() {
    guard setupTestState == .recording, setupTestTask == nil else { return }

    do {
      let audioURL = try audioRecorder.stop()
      setupTestState = .processing
      setupTestTask = Task { @MainActor [weak self] in
        guard let self else { return }
        defer {
          _ = try? OwnedRecordingFile.removeIfOwned(audioURL)
          setupTestTask = nil
        }
        guard !Task.isCancelled else {
          setupTestState = .idle
          return
        }

        do {
          let rawTranscript: String
          switch recommendedLocalProvider {
          case .parakeet:
            rawTranscript = try await parakeet.transcribe(audioURL, progress: { _ in })
            parakeetStatus = .ready
          case .whisper:
            rawTranscript = try await whisper.transcribe(audioURL, progress: { _ in })
            whisperStatus = .ready
          case .openAI, .xAI, .groq:
            return
          }

          guard !Task.isCancelled else { return }
          let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !transcript.isEmpty else { throw DictationWorkflowError.noSpeechDetected }
          setupTestState = .success(transcript)
          lastError = nil
        } catch is CancellationError {
          setupTestState = .idle
        } catch {
          guard !Task.isCancelled else { return }
          setupTestState = .failure(error.localizedDescription)
          lastError = error.localizedDescription
        }
      }
    } catch {
      setupTestState = .failure(error.localizedDescription)
      lastError = error.localizedDescription
    }
  }

  func cancelSetupTest() {
    setupTestTask?.cancel()
    if setupTestState == .recording,
      audioRecorder.hasActiveSession,
      let audioURL = try? audioRecorder.stop()
    {
      _ = try? OwnedRecordingFile.removeIfOwned(audioURL)
    }
    if setupTestState == .recording || setupTestState == .processing {
      setupTestState = .idle
    }
  }

  func completeSetup() {
    refreshSetupState()
    guard setupReadiness.canComplete else {
      lastError = "Finish every Setup check before enabling dictation."
      return
    }

    let provider = recommendedLocalProvider
    let insertionMode: InsertionMode
    let hotKey: HotKeyConfiguration
    switch selectedSetupExperience {
    case .full:
      insertionMode = .activeApplication
      hotKey = .rightOption
    case .minimal:
      insertionMode = .clipboardOnly
      hotKey = preferences.hotKey
    }

    do {
      let hotKeyService = try configuredHotKeyService()
      try hotKeyService.register(hotKey)
      pendingHotKeyConfiguration = nil
      hotKeyRegistrationError = nil
    } catch {
      let message = error.localizedDescription
      hotKeyRegistrationError = message
      lastError = message
      return
    }

    preferences.provider = provider
    preferences.insertionMode = insertionMode
    preferences.hotKey = hotKey
    preferences.completeSetup(experience: selectedSetupExperience)
    lastError = nil
    setupWindow.close()
  }

  func requestAccessibilityPermission() {
    isAccessibilityGranted = insertionService.requestAccessibilityPermission()
    if isAccessibilityGranted {
      refreshPermissionsAndHotKey()
    }
    beginAccessibilityRecovery()
  }

  func openAccessibilitySettings() {
    beginAccessibilityRecovery()
    openPrivacyPane("Privacy_Accessibility")
  }

  func observeAccessibilityPermission() {
    refreshSetupState()
    guard !isAccessibilityGranted else { return }
    beginAccessibilityRecovery()
  }

  func openMicrophoneSettings() {
    openPrivacyPane("Privacy_Microphone")
  }

  private func refreshPermissionsAndHotKey() {
    microphonePermission = audioRecorder.permissionState
    refreshAccessibilityPermission()
    guard preferences.hasCompletedSetup else { return }
    guard
      preferences.hotKey.isRightOptionOnly,
      hotKeyService?.currentConfiguration != preferences.hotKey
    else { return }
    updateHotKeyRegistration(preferences.hotKey)
  }

  private func applicationDidBecomeActive() {
    refreshPermissionsAndHotKey()
    if isSetupVisible,
      selectedSetupExperience == .full,
      !isAccessibilityGranted
    {
      beginAccessibilityRecovery()
    }
  }

  private func refreshAccessibilityPermission() {
    isAccessibilityGranted = insertionService.isAccessibilityGranted
  }

  func retryHotKeyRegistration() {
    guard preferences.hasCompletedSetup else {
      showSetup()
      return
    }
    updateHotKeyRegistration(preferences.hotKey)
    beginAccessibilityRecovery()
  }

  private func rearmHotKeyAfterSystemInterruption() {
    guard preferences.hasCompletedSetup else { return }
    guard preferences.hotKey.isRightOptionOnly else { return }
    guard
      let hotKeyService,
      hotKeyService.currentConfiguration == preferences.hotKey
    else {
      refreshPermissionsAndHotKey()
      if !isSelectedHotKeyActive {
        beginAccessibilityRecovery()
      }
      return
    }

    do {
      try hotKeyService.rearmAfterSystemInterruption()
      if lastError == hotKeyRegistrationError {
        lastError = nil
      }
      hotKeyRegistrationError = nil
    } catch {
      let message = error.localizedDescription
      handleHotKeyMonitorFailure(message)
      return
    }
    objectWillChange.send()
  }

  func setShortcutRecordingActive(_ active: Bool) {
    hotKeyService?.setSuspended(active || isSetupVisible)
  }

  func copyLastTranscript() {
    guard !lastTranscript.isEmpty else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(lastTranscript, forType: .string) else {
      lastError = TextInsertionError.clipboardWriteFailed.localizedDescription
      return
    }
  }

  func isAPIKeyConfigured(for provider: CloudAPIProvider) -> Bool {
    configuredCloudProviders.contains(provider)
  }

  func saveAPIKey(_ value: String, for provider: CloudAPIProvider) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CloudTranscriptionError.missingAPIKey(provider: provider.title)
    }
    try KeychainStore.save(
      trimmed,
      service: AppConstants.bundleIdentifier,
      account: provider.keychainAccount
    )
    configuredCloudProviders.insert(provider)
    if lastError == missingAPIKeyMessage(for: provider) {
      lastError = nil
    }
  }

  func deleteAPIKey(for provider: CloudAPIProvider) throws {
    try KeychainStore.delete(
      service: AppConstants.bundleIdentifier,
      account: provider.keychainAccount
    )
    configuredCloudProviders.remove(provider)
  }

  func downloadModel(_ provider: TranscriptionProvider) {
    guard provider.isLocal else { return }
    guard setupTestTask == nil else {
      lastError = "Wait for the Setup transcription test to finish."
      return
    }
    guard setupTestState != .recording, setupTestState != .processing else {
      lastError = "Finish the Setup transcription test before changing models."
      return
    }
    guard dictationState.isIdle else {
      lastError = "Finish the current dictation before changing models."
      return
    }
    guard modelTask == nil else {
      lastError = "Wait for the current model operation to finish."
      return
    }

    modelStatusRefreshID = nil
    let operationID = UUID()
    modelOperationID = operationID
    modelTask = Task { [weak self] in
      guard let self else { return }
      defer { completeModelOperation(operationID) }
      do {
        switch provider {
        case .parakeet:
          parakeetStatus = .downloading(0)
          try await parakeet.prepare(
            progress: modelProgress(for: .parakeet, modelOperationID: operationID)
          )
          guard modelOperationID == operationID else { return }
          parakeetStatus = .ready
        case .whisper:
          whisperStatus = .downloading(0)
          try await whisper.prepare(
            progress: modelProgress(for: .whisper, modelOperationID: operationID)
          )
          guard modelOperationID == operationID else { return }
          whisperStatus = .ready
        case .openAI, .xAI, .groq:
          break
        }
        lastError = nil
      } catch is CancellationError {
        guard modelOperationID == operationID else { return }
        await reconcileModelStatus(provider, operationID: operationID)
      } catch {
        guard modelOperationID == operationID else { return }
        setModelFailure(provider, message: error.localizedDescription)
        lastError = error.localizedDescription
      }
    }
  }

  func deleteModel(_ provider: TranscriptionProvider) {
    guard provider.isLocal else { return }
    guard setupTestTask == nil else {
      lastError = "Wait for the Setup transcription test to finish."
      return
    }
    guard setupTestState != .recording, setupTestState != .processing else {
      lastError = "Finish the Setup transcription test before changing models."
      return
    }
    guard dictationState.isIdle else {
      lastError = "Finish the current dictation before changing models."
      return
    }
    guard modelTask == nil else {
      lastError = "Wait for the current model operation to finish."
      return
    }

    modelStatusRefreshID = nil
    let operationID = UUID()
    modelOperationID = operationID
    modelTask = Task { [weak self] in
      guard let self else { return }
      defer { completeModelOperation(operationID) }
      do {
        switch provider {
        case .parakeet:
          try await parakeet.deleteModel()
          guard modelOperationID == operationID else { return }
          parakeetStatus = .notDownloaded
        case .whisper:
          try await whisper.deleteModel()
          guard modelOperationID == operationID else { return }
          whisperStatus = .notDownloaded
        case .openAI, .xAI, .groq:
          break
        }
        lastError = nil
      } catch is CancellationError {
        guard modelOperationID == operationID else { return }
        await reconcileModelStatus(provider, operationID: operationID)
      } catch {
        guard modelOperationID == operationID else { return }
        setModelFailure(provider, message: error.localizedDescription)
        lastError = error.localizedDescription
      }
    }
  }

  func refreshModelStatuses() {
    guard modelTask == nil, dictationState.isIdle else { return }
    let refreshID = UUID()
    modelStatusRefreshID = refreshID
    Task { [weak self] in
      guard let self else { return }
      let parakeetExists = await parakeet.modelExists()
      guard
        modelTask == nil,
        dictationState.isIdle,
        modelStatusRefreshID == refreshID
      else { return }
      parakeetStatus = parakeetExists ? .ready : .notDownloaded

      let whisperExists = await whisper.modelExists()
      guard
        modelTask == nil,
        dictationState.isIdle,
        modelStatusRefreshID == refreshID
      else { return }
      whisperStatus = whisperExists ? .ready : .notDownloaded
      modelStatusRefreshID = nil
    }
  }

  private func hotKeyPressed() {
    guard dictationState.isIdle, modelTask == nil else { return }
    guard !isSetupVisible else { return }
    guard preferences.hasCompletedSetup else {
      showSetup()
      return
    }

    microphonePermission = audioRecorder.permissionState
    guard microphonePermission == .granted else {
      lastError = "Microphone access is required. Open FreeFlow Setup to continue."
      showSetup()
      return
    }

    guard isSelectedProviderReady else {
      if let provider = preferences.provider.cloudAPIProvider {
        lastError = missingAPIKeyMessage(for: provider)
      } else {
        lastError = "The selected transcription engine is not ready. Open FreeFlow Setup first."
        showSetup()
      }
      return
    }

    let sessionID = UUID()
    let configuration = DictationConfiguration(
      provider: preferences.provider,
      openAIModel: preferences.openAIModel,
      groqModel: preferences.groqModel,
      insertionMode: preferences.insertionMode,
      removeFillers: preferences.removeFillers
    )
    modelStatusRefreshID = nil
    isHotKeyHeld = true
    capturedTarget = insertionService.captureTarget()
    capturedScreen = pillWindow.activeScreen()
    dictationState = .starting(sessionID)
    lastError = nil
    cancelPillDismiss()
    pillModel.phase = .recording
    pillModel.audioLevel = 0
    pillWindow.show(on: capturedScreen)

    dictationTask = Task { [weak self] in
      guard let self else { return }
      await runDictation(sessionID, configuration: configuration)
    }
  }

  private func hotKeyReleased() {
    isHotKeyHeld = false
    releaseContinuation?.resume(returning: true)
    releaseContinuation = nil
  }

  private func runDictation(
    _ sessionID: UUID,
    configuration: DictationConfiguration
  ) async {
    defer { completeDictationSession(sessionID) }

    do {
      try await audioRecorder.start { [weak self] level in
        guard self?.dictationState.sessionID == sessionID else { return }
        self?.pillModel.audioLevel = level
      }
      guard dictationState.sessionID == sessionID else { return }

      dictationState = .recording(sessionID)
      guard await waitForHotKeyRelease(sessionID: sessionID) else {
        throw DictationWorkflowError.recordingTimedOut
      }
      guard dictationState.sessionID == sessionID else { return }

      dictationState = .finishing(sessionID)
      let audioURL = try audioRecorder.stop()
      pillModel.audioLevel = 0
      pillModel.phase = .processing
      dictationState = .processing(sessionID)
      try await transcribeAndInsert(
        audioURL,
        target: capturedTarget,
        sessionID: sessionID,
        configuration: configuration
      )
    } catch {
      guard dictationState.sessionID == sessionID else { return }
      presentFailure(error)
    }
  }

  private func waitForHotKeyRelease(sessionID: UUID) async -> Bool {
    guard isHotKeyHeld else { return true }

    releaseTimeoutTask?.cancel()
    releaseTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(300))
      } catch {
        return
      }
      guard let self, dictationState.sessionID == sessionID else { return }
      isHotKeyHeld = false
      releaseContinuation?.resume(returning: false)
      releaseContinuation = nil
    }

    let releasedPhysically = await withCheckedContinuation { continuation in
      guard isHotKeyHeld else {
        continuation.resume(returning: true)
        return
      }
      releaseContinuation = continuation
    }
    releaseTimeoutTask?.cancel()
    releaseTimeoutTask = nil
    return releasedPhysically
  }

  private func transcribeAndInsert(
    _ audioURL: URL,
    target: TextInsertionTarget?,
    sessionID: UUID,
    configuration: DictationConfiguration
  ) async throws {
    defer { _ = try? OwnedRecordingFile.removeIfOwned(audioURL) }

    let rawTranscript: String

    let provider = configuration.provider
    do {
      switch provider {
      case .parakeet:
        rawTranscript = try await parakeet.transcribe(audioURL, progress: { _ in })
        guard dictationState.sessionID == sessionID else { return }
        parakeetStatus = .ready
      case .whisper:
        rawTranscript = try await whisper.transcribe(audioURL, progress: { _ in })
        guard dictationState.sessionID == sessionID else { return }
        whisperStatus = .ready
      case .openAI:
        rawTranscript = try await transcribeWithCloud(
          audioURL,
          service: .openAI(model: configuration.openAIModel.rawValue)
        )
      case .xAI:
        rawTranscript = try await transcribeWithCloud(
          audioURL,
          service: .xAI
        )
      case .groq:
        rawTranscript = try await transcribeWithCloud(
          audioURL,
          service: .groq(model: configuration.groqModel.rawValue)
        )
      }
    } catch {
      await reconcileDictationModelStatus(provider, error: error, sessionID: sessionID)
      throw error
    }
    guard dictationState.sessionID == sessionID else { return }
    pillModel.phase = .processing

    let transcript =
      configuration.removeFillers
      ? TranscriptSanitizer.removingAcousticFillers(from: rawTranscript)
      : rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transcript.isEmpty else {
      throw DictationWorkflowError.noSpeechDetected
    }

    lastTranscript = transcript
    let insertionResult = try await insertionService.insert(
      transcript,
      into: target,
      mode: configuration.insertionMode
    )
    guard dictationState.sessionID == sessionID else { return }
    pillModel.phase = .success(insertionResult)
    lastError = nil
    schedulePillDismiss(after: .milliseconds(900))
  }

  private func modelProgress(
    for provider: TranscriptionProvider,
    modelOperationID operationID: UUID
  ) -> @Sendable (Double) -> Void {
    { [weak self] progress in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.modelOperationID == operationID else { return }

        switch provider {
        case .parakeet: self.parakeetStatus = .downloading(progress)
        case .whisper: self.whisperStatus = .downloading(progress)
        case .openAI, .xAI, .groq: break
        }
      }
    }
  }

  private func presentFailure(_ error: Error) {
    let message = error.localizedDescription
    lastError = message
    pillModel.phase = .failure(message)
    pillWindow.show(on: capturedScreen)
    schedulePillDismiss(after: .seconds(2))
  }

  private func completeDictationSession(_ sessionID: UUID) {
    guard dictationState.sessionID == sessionID else { return }

    if audioRecorder.hasActiveSession {
      if let audioURL = try? audioRecorder.stop() {
        _ = try? OwnedRecordingFile.removeIfOwned(audioURL)
      }
    }
    releaseTimeoutTask?.cancel()
    releaseTimeoutTask = nil
    releaseContinuation?.resume(returning: false)
    releaseContinuation = nil
    capturedTarget = nil
    capturedScreen = nil
    isHotKeyHeld = false
    pillModel.audioLevel = 0
    dictationState = .idle
    dictationTask = nil
    applyPendingHotKeyRegistration()
  }

  private func completeModelOperation(_ operationID: UUID) {
    guard modelOperationID == operationID else { return }
    modelOperationID = nil
    modelTask = nil
  }

  private func updateHotKeyRegistration(_ configuration: HotKeyConfiguration) {
    guard preferences.hasCompletedSetup else { return }

    if !configuration.isRightOptionOnly {
      cancelAccessibilityRecovery()
    }

    guard dictationState.isIdle else {
      pendingHotKeyConfiguration = configuration
      return
    }

    do {
      let hotKeyService = try configuredHotKeyService()
      try hotKeyService.register(configuration)
      pendingHotKeyConfiguration = nil
      if lastError == hotKeyRegistrationError {
        lastError = nil
      }
      hotKeyRegistrationError = nil
      if configuration.isRightOptionOnly {
        cancelAccessibilityRecovery()
      }
    } catch {
      let message = error.localizedDescription
      if let fallback = hotKeyService?.currentConfiguration, fallback != configuration {
        Task { @MainActor [weak self] in
          guard let self, preferences.hotKey == configuration else { return }
          preferences.hotKey = fallback
          hotKeyRegistrationError = message
          lastError = message
        }
      }
      hotKeyRegistrationError = message
      lastError = message
    }
  }

  private func beginAccessibilityRecovery() {
    accessibilityRecoveryTask?.cancel()
    accessibilityRecoveryTask = nil
    accessibilityRecoveryID = nil

    let setupNeedsPermission =
      isSetupVisible
      && selectedSetupExperience == .full
    let runtimeNeedsHotKey =
      preferences.hasCompletedSetup
      && preferences.hotKey.isRightOptionOnly
      && hotKeyService?.currentConfiguration != preferences.hotKey
    guard setupNeedsPermission || runtimeNeedsHotKey else { return }

    let recoveryID = UUID()
    accessibilityRecoveryID = recoveryID

    accessibilityRecoveryTask = Task { @MainActor [weak self] in
      for attempt in 1...Self.accessibilityRecoveryAttemptCount {
        guard !Task.isCancelled, self?.accessibilityRecoveryID == recoveryID else { return }
        self?.refreshPermissionsAndHotKey()
        guard let self else { return }
        let setupIsAwaitingPermission =
          isSetupVisible
          && selectedSetupExperience == .full
        let runtimeIsAwaitingHotKey =
          preferences.hasCompletedSetup
          && preferences.hotKey.isRightOptionOnly
          && hotKeyService?.currentConfiguration != preferences.hotKey

        guard setupIsAwaitingPermission || runtimeIsAwaitingHotKey else {
          self.cancelAccessibilityRecovery()
          return
        }

        if setupIsAwaitingPermission {
          if isAccessibilityGranted {
            self.cancelAccessibilityRecovery()
            return
          }
        } else if isSelectedHotKeyActive {
          self.cancelAccessibilityRecovery()
          return
        }

        guard attempt < Self.accessibilityRecoveryAttemptCount else {
          self.finishAccessibilityRecovery(recoveryID)
          return
        }

        do {
          try await Task.sleep(for: Self.accessibilityRecoveryInterval)
        } catch {
          return
        }
      }
    }
  }

  private func finishAccessibilityRecovery(_ recoveryID: UUID) {
    guard accessibilityRecoveryID == recoveryID else { return }
    accessibilityRecoveryID = nil
    accessibilityRecoveryTask = nil
    objectWillChange.send()
  }

  private func cancelAccessibilityRecovery() {
    guard accessibilityRecoveryTask != nil || accessibilityRecoveryID != nil else { return }
    accessibilityRecoveryID = nil
    accessibilityRecoveryTask?.cancel()
    accessibilityRecoveryTask = nil
  }

  private func handleHotKeyMonitorFailure(_ message: String) {
    hotKeyRegistrationError = message
    lastError = message
    objectWillChange.send()
    if preferences.hotKey.isRightOptionOnly {
      beginAccessibilityRecovery()
    }
  }

  private func configuredHotKeyService() throws -> GlobalHotKeyService {
    if let hotKeyService { return hotKeyService }

    let hotKeyService = try GlobalHotKeyService()
    hotKeyService.onPress = { [weak self] in self?.hotKeyPressed() }
    hotKeyService.onRelease = { [weak self] in self?.hotKeyReleased() }
    hotKeyService.onFailure = { [weak self] message in
      self?.handleHotKeyMonitorFailure(message)
    }
    self.hotKeyService = hotKeyService
    return hotKeyService
  }

  private func shutdownForTermination() {
    accessibilityRecoveryTask?.cancel()
    accessibilityRecoveryTask = nil
    hotKeyService?.shutdown()
    hotKeyService = nil
  }

  private func applyPendingHotKeyRegistration() {
    guard preferences.hasCompletedSetup else {
      pendingHotKeyConfiguration = nil
      return
    }
    guard let configuration = pendingHotKeyConfiguration else { return }
    pendingHotKeyConfiguration = nil
    updateHotKeyRegistration(configuration)
  }

  private func reconcileModelStatus(
    _ provider: TranscriptionProvider,
    operationID: UUID
  ) async {
    switch provider {
    case .parakeet:
      let exists = await parakeet.modelExists()
      guard modelOperationID == operationID else { return }
      parakeetStatus = exists ? .ready : .notDownloaded
    case .whisper:
      let exists = await whisper.modelExists()
      guard modelOperationID == operationID else { return }
      whisperStatus = exists ? .ready : .notDownloaded
    case .openAI, .xAI, .groq:
      break
    }
  }

  private func reconcileDictationModelStatus(
    _ provider: TranscriptionProvider,
    error: Error,
    sessionID: UUID
  ) async {
    switch provider {
    case .parakeet:
      let exists = await parakeet.modelExists()
      guard dictationState.sessionID == sessionID else { return }
      parakeetStatus = exists ? .ready : .failed(error.localizedDescription)
    case .whisper:
      let exists = await whisper.modelExists()
      guard dictationState.sessionID == sessionID else { return }
      whisperStatus = exists ? .ready : .failed(error.localizedDescription)
    case .openAI, .xAI, .groq:
      break
    }
  }

  private func schedulePillDismiss(after delay: Duration) {
    cancelPillDismiss()
    let dismissID = UUID()
    pillDismissID = dismissID
    pillDismissTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self, pillDismissID == dismissID else { return }
      pillModel.phase = .hidden
      pillWindow.hide()
      pillDismissID = nil
      pillDismissTask = nil
    }
  }

  private func cancelPillDismiss() {
    pillDismissTask?.cancel()
    pillDismissTask = nil
    pillDismissID = nil
  }

  private func setModelFailure(_ provider: TranscriptionProvider, message: String) {
    switch provider {
    case .parakeet: parakeetStatus = .failed(message)
    case .whisper: whisperStatus = .failed(message)
    case .openAI, .xAI, .groq: break
    }
  }

  private var isSelectedProviderReady: Bool {
    switch preferences.provider {
    case .parakeet:
      return parakeetStatus.isReady
    case .whisper:
      return whisperStatus.isReady
    case .openAI, .xAI, .groq:
      guard let provider = preferences.provider.cloudAPIProvider else { return false }
      return configuredCloudProviders.contains(provider)
    }
  }

  private func transcribeWithCloud(
    _ audioURL: URL,
    service: CloudTranscriptionService
  ) async throws -> String {
    let provider = service.credentialProvider
    guard let apiKey = try storedAPIKey(for: provider) else {
      throw CloudTranscriptionError.missingAPIKey(provider: provider.title)
    }
    let uploadURL = try await cloudAudioFilePreparer.prepare(audioURL)
    defer { _ = try? OwnedRecordingFile.removeIfOwned(uploadURL) }
    return try await cloudTranscriber.transcribe(
      uploadURL,
      apiKey: apiKey,
      service: service
    )
  }

  private func refreshAPIKeyConfiguration() {
    configuredCloudProviders = Set(
      CloudAPIProvider.allCases.filter { provider in
        guard let key = try? storedAPIKey(for: provider) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    )
  }

  private func missingAPIKeyMessage(for provider: CloudAPIProvider) -> String {
    "Add your \(provider.title) API key in Settings > Cloud."
  }

  private func storedAPIKey(for provider: CloudAPIProvider) throws -> String? {
    try KeychainStore.read(
      service: AppConstants.bundleIdentifier,
      account: provider.keychainAccount
    )
  }

  private func openPrivacyPane(_ anchor: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

}
