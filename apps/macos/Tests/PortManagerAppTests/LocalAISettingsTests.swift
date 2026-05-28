import Testing
@testable import PortManagerApp

@Test func defaultAISettingsPreferCodexInAuto() {
  let settings = LocalAISettings.defaults

  #expect(settings.providerMode == .auto)
  #expect(settings.preferCodexInAuto)
  #expect(settings.promptTemplate.contains("{localEvidence}"))
}

@Test func ollamaRecommendationPrefersConfiguredModel() {
  let model = LocalAIInspectionService.recommendedOllamaModel(
    from: ["llama3:latest", "qwen3-coder:30b"],
    configuredModel: "llama3:latest"
  )

  #expect(model == "llama3:latest")
}

@Test func ollamaRecommendationSkipsEmbeddingModels() {
  let model = LocalAIInspectionService.recommendedOllamaModel(
    from: ["qwen3-embedding:8b", "qwen3-coder:30b", "llama3:latest"],
    configuredModel: ""
  )

  #expect(model == "qwen3-coder:30b")
}

@Test func ollamaRecommendationReturnsNilForOnlyEmbeddingModels() {
  let model = LocalAIInspectionService.recommendedOllamaModel(
    from: ["qwen3-embedding:8b", "embeddinggemma:latest"],
    configuredModel: ""
  )

  #expect(model == nil)
}
