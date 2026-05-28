import Foundation
import Observation

enum LocalAIProviderMode: String, CaseIterable, Codable, Identifiable {
  case off
  case auto
  case ollama
  case codexCLI

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off:
      return "Off"
    case .auto:
      return "Auto"
    case .ollama:
      return "Ollama"
    case .codexCLI:
      return "Codex CLI"
    }
  }
}

struct LocalAISettings: Codable, Hashable {
  var providerMode: LocalAIProviderMode
  var onlineResearchEnabled: Bool
  var ollamaBaseURL: String
  var ollamaModel: String
  var preferCodexInAuto: Bool
  var codexCommand: String
  var promptTemplate: String

  static let defaults = LocalAISettings(
    providerMode: .auto,
    onlineResearchEnabled: true,
    ollamaBaseURL: "http://127.0.0.1:11434",
    ollamaModel: "",
    preferCodexInAuto: true,
    codexCommand: "codex",
    promptTemplate: defaultPromptTemplate
  )

  static let defaultPromptTemplate = """
  You are Port Manager's local AI helper. Explain this macOS port/process cluster for a developer.
  Do not execute commands. Do not suggest killing system processes unless there is a clear risk.
  Return 3 short bullets: likely purpose, what looks normal or unusual, and what to check next.

  Cluster: {cluster}
  Local evidence:
  {localEvidence}

  Current warnings:
  {warnings}

  Online source snippets:
  {onlineSources}
  """

  static func load(userDefaults: UserDefaults = .standard) -> LocalAISettings {
    guard let data = userDefaults.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode(LocalAISettings.self, from: data)
    else {
      return .defaults
    }
    return decoded
  }

  func save(userDefaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    userDefaults.set(data, forKey: Self.defaultsKey)
  }

  private static let defaultsKey = "PortManagerLocalAISettings"
}

@MainActor
@Observable
final class LocalAISettingsStore {
  var settings: LocalAISettings {
    didSet {
      guard isLoaded else { return }
      settings.save(userDefaults: userDefaults)
    }
  }
  var isChecking = false
  var statusMessage = "Not checked"
  var availableOllamaModels: [String] = []
  var recommendedOllamaModel: String?

  private let userDefaults: UserDefaults
  private var isLoaded = false

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    settings = .load(userDefaults: userDefaults)
    isLoaded = true
  }

  func reload() {
    isLoaded = false
    settings = .load(userDefaults: userDefaults)
    isLoaded = true
  }

  func checkProviders() async {
    isChecking = true
    defer { isChecking = false }
    let check = await LocalAIInspectionService.providerCheck(settings: settings)
    availableOllamaModels = check.ollamaModels
    recommendedOllamaModel = check.recommendedOllamaModel
    statusMessage = check.message
    if let recommendedOllamaModel,
       settings.ollamaModel.isEmpty
        || !LocalAIInspectionService.isGenerativeOllamaModel(settings.ollamaModel)
        || !availableOllamaModels.contains(settings.ollamaModel) {
      settings.ollamaModel = recommendedOllamaModel
    }
  }

  func resetPromptTemplate() {
    settings.promptTemplate = LocalAISettings.defaultPromptTemplate
  }
}

struct PortInspectionAI: Codable, Hashable {
  let provider: String
  let model: String?
  let generatedAt: Date
  let summary: String
}
