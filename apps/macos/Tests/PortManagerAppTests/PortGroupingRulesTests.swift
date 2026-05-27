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

@Test func defaultRulesFoldGoalBuddyFromProcessEvidence() {
  let port = listeningPort(
    processName: "node",
    command: "/opt/homebrew/bin/node",
    bind: PortBind(id: "goalbuddy", host: "127.0.0.1", port: 41737, proto: "TCP", commonPort: nil, ownerPid: 41737, ownerName: "node"),
    displayGroup: PortDisplayGroup(id: "other", name: "Other", rank: 100)
  )
  let enriched = ListeningPort(
    id: port.id,
    pid: port.pid,
    status: port.status,
    processName: port.processName,
    user: port.user,
    uid: port.uid,
    parentPid: port.parentPid,
    command: port.command,
    arguments: "node /Users/patrickjs/.codex/plugins/goalbuddy/server.js",
    currentDirectory: "/Users/patrickjs/.codex/plugins/goalbuddy",
    launchOriginator: port.launchOriginator,
    binds: port.binds,
    ownerCount: port.ownerCount,
    entryCount: port.entryCount,
    groupReason: port.groupReason,
    displayGroup: port.displayGroup,
    ownershipEvidence: port.ownershipEvidence,
    ownershipSummaryOverride: port.ownershipSummaryOverride,
    ownershipConfidenceOverride: port.ownershipConfidenceOverride
  )

  #expect(portClusterTitle(for: enriched, rules: PortGroupingRule.defaults) == "GoalBuddy")
  #expect(configuredDisplayGroup(for: enriched, rules: PortGroupingRule.defaults).name == "Web Dev")
}
