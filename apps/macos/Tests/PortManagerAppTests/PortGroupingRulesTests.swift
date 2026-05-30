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

@Test func customGroupsCanReceiveMatchingRules() {
  let groups = [
    PortDisplayGroup(id: "developer-tools", name: "Developer Tools", rank: 15),
    PortDisplayGroup.other
  ]
  let rules = [
    PortGroupingRule(
      id: "custom-cursor",
      isEnabled: true,
      match: "cursor helper",
      matchMode: .prefix,
      title: "Cursor",
      displayGroupID: "developer-tools"
    )
  ]
  let port = listeningPort(
    processName: "Cursor Helper (Plugin)",
    command: "Cursor Helper (Plugin)",
    bind: PortBind(id: "cursor", host: "127.0.0.1", port: 40423, proto: "TCP", commonPort: nil, ownerPid: 40423, ownerName: "Cursor Helper (Plugin)"),
    displayGroup: .other
  )

  #expect(configuredDisplayGroup(for: port, rules: rules, groups: groups).name == "Developer Tools")
}

@Test func groupIDsAreStableAndReadable() {
  let existing: Set<String> = ["developer-tools"]

  #expect(PortGroupingCategories.stableID(for: "Developer Tools", existingIDs: existing) == "developer-tools-2")
  #expect(PortGroupingCategories.stableID(for: "AI Services", existingIDs: existing) == "ai-services")
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
