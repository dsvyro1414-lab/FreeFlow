import Combine
import Foundation
import FreeFlowCore

@MainActor
final class PreferencesStore: ObservableObject {
  private enum Keys {
    static let provider = "transcriptionProvider"
    static let insertionMode = "insertionMode"
    static let hotKey = "hotKeyConfiguration"
    static let removeFillers = "removeAcousticFillers"
    static let openAIModel = "openAITranscriptionModel"
    static let groqModel = "groqTranscriptionModel"
    static let setupVersion = "setupVersion"
    static let setupExperience = "setupExperience"
  }

  @Published var provider: TranscriptionProvider {
    didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
  }

  @Published var insertionMode: InsertionMode {
    didSet { defaults.set(insertionMode.rawValue, forKey: Keys.insertionMode) }
  }

  @Published var hotKey: HotKeyConfiguration {
    didSet {
      if let data = try? JSONEncoder().encode(hotKey) {
        defaults.set(data, forKey: Keys.hotKey)
      }
    }
  }

  @Published var removeFillers: Bool {
    didSet { defaults.set(removeFillers, forKey: Keys.removeFillers) }
  }

  @Published var openAIModel: OpenAITranscriptionModel {
    didSet { defaults.set(openAIModel.rawValue, forKey: Keys.openAIModel) }
  }

  @Published var groqModel: GroqTranscriptionModel {
    didSet { defaults.set(groqModel.rawValue, forKey: Keys.groqModel) }
  }

  @Published private(set) var setupVersion: Int {
    didSet { defaults.set(setupVersion, forKey: Keys.setupVersion) }
  }

  @Published private(set) var setupExperience: SetupExperience {
    didSet { defaults.set(setupExperience.rawValue, forKey: Keys.setupExperience) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let savedProvider = defaults.string(forKey: Keys.provider)
      .flatMap(TranscriptionProvider.init(rawValue:))
    if PlatformSupport.supportsParakeet {
      provider = savedProvider ?? .parakeet
    } else {
      provider = savedProvider == .parakeet ? .whisper : (savedProvider ?? .whisper)
    }

    insertionMode =
      defaults.string(forKey: Keys.insertionMode)
      .flatMap(InsertionMode.init(rawValue:))
      ?? .activeApplication

    if let data = defaults.data(forKey: Keys.hotKey),
      let value = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data)
    {
      hotKey = value
    } else {
      hotKey = .defaultValue
    }

    removeFillers = defaults.object(forKey: Keys.removeFillers) as? Bool ?? true
    openAIModel =
      defaults.string(forKey: Keys.openAIModel)
      .flatMap(OpenAITranscriptionModel.init(rawValue:))
      ?? .mini
    groqModel =
      defaults.string(forKey: Keys.groqModel)
      .flatMap(GroqTranscriptionModel.init(rawValue:))
      ?? .turbo

    setupVersion = defaults.integer(forKey: Keys.setupVersion)
    setupExperience =
      defaults.string(forKey: Keys.setupExperience)
      .flatMap(SetupExperience.init(rawValue:))
      ?? .full
  }

  var hasCompletedSetup: Bool { setupVersion >= 1 }

  func completeSetup(experience: SetupExperience) {
    setupExperience = experience
    setupVersion = 1
  }
}
