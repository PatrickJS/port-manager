import Testing
@testable import PortManagerApp

@Test func defaultRulesFoldOllamaCaseVariants() {
  let rules = PortGroupingRule.defaults

  #expect(normalizedPortClusterTitle("ollama", rules: rules) == "Ollama")
  #expect(normalizedPortClusterTitle("Ollama", rules: rules) == "Ollama")
}

@Test func defaultRulesFoldCursorHelpers() {
  let rules = PortGroupingRule.defaults

  #expect(normalizedPortClusterTitle("Cursor Helper (Plugin)", rules: rules) == "Cursor")
  #expect(normalizedPortClusterTitle("Cursor Helper (Renderer)", rules: rules) == "Cursor")
}

@Test func customRulesCanRenameClusters() {
  let rules = [
    PortGroupingRule(
      id: "test-ollama",
      isEnabled: true,
      match: "ollama",
      matchMode: .exact,
      title: "Local Models",
      displayGroupID: "ai"
    )
  ]

  #expect(normalizedPortClusterTitle("ollama", rules: rules) == "Local Models")
}
