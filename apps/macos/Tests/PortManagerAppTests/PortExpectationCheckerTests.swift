import Testing
@testable import PortManagerApp

@Test func publicOllamaBindingWarns() {
  let port = listeningPort(
    processName: "ollama",
    command: "/usr/local/bin/ollama",
    bind: PortBind(id: "public", host: "*", port: 11434, proto: "TCP", commonPort: nil, ownerPid: 42, ownerName: "ollama"),
    displayGroup: PortDisplayGroup(id: "ai", name: "AI", rank: 30)
  )

  let warnings = PortExpectationChecker.warnings(for: [port], title: "Ollama")

  #expect(warnings.contains { $0.message.contains("localhost-only") })
}

@Test func osAppleOutsideSystemWarns() {
  let port = listeningPort(
    processName: "ControlCenter",
    command: "/tmp/ControlCenter",
    bind: PortBind(id: "control", host: "127.0.0.1", port: 5000, proto: "TCP", commonPort: nil, ownerPid: 100, ownerName: "ControlCenter"),
    displayGroup: PortDisplayGroup(id: "os-apple", name: "OS / Apple", rank: 120)
  )

  let warnings = PortExpectationChecker.warnings(for: [port], title: "ControlCenter")

  #expect(warnings.contains { $0.message.contains("not under /System") })
}

private func listeningPort(
  processName: String,
  command: String,
  bind: PortBind,
  displayGroup: PortDisplayGroup
) -> ListeningPort {
  ListeningPort(
    id: "\(processName)-\(bind.port)",
    pid: bind.ownerPid ?? 1,
    status: .listening,
    processName: processName,
    user: "patrickjs",
    uid: 501,
    parentPid: 1,
    command: command,
    arguments: command,
    currentDirectory: "/",
    launchOriginator: nil,
    binds: [bind],
    ownerCount: 1,
    entryCount: 1,
    groupReason: nil,
    displayGroup: displayGroup,
    ownershipEvidence: [],
    ownershipSummaryOverride: nil,
    ownershipConfidenceOverride: nil
  )
}
