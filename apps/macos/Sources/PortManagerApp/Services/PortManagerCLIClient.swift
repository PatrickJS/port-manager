import Foundation

struct PortManagerCLIClient {
  private let config: PortManagerAppConfig

  init(config: PortManagerAppConfig = .load()) {
    self.config = config
  }

  func listPorts() async throws -> [ListeningPort] {
    let data = try await runPortManager(arguments: ["list", "--json"])
    let envelope = try JSONDecoder().decode(CLIEnvelope<CLIListResult>.self, from: data)
    guard envelope.ok else {
      throw PortManagerCLIError.commandFailed(envelope.error?.message ?? "port-manager list failed")
    }

    if let portGroups = envelope.result.portGroups {
      return portGroups.map { group in
        listeningPort(from: group)
      }
    }

    return envelope.result.ports.map { entry in
      listeningPort(from: entry)
    }
  }

  func killPort(_ port: ListeningPort) async throws -> KillPortResult {
    guard let primaryPort = port.primaryPort else {
      throw PortManagerCLIError.commandFailed("Selected process has no port binding")
    }

    var arguments = [
      "kill",
      "\(primaryPort)"
    ]
    if port.ownerCount == 1, port.pid > 0 {
      arguments += ["--pid", "\(port.pid)"]
    }
    arguments.append("--json")

    let data = try await runPortManager(arguments: arguments)
    let envelope = try JSONDecoder().decode(CLIEnvelope<KillPortResult>.self, from: data)
    guard envelope.ok else {
      throw PortManagerCLIError.commandFailed(envelope.error?.message ?? "port-manager kill failed")
    }

    return envelope.result
  }

  private func runPortManager(arguments: [String]) async throws -> Data {
    try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: config.pnpmPath)
      process.currentDirectoryURL = URL(fileURLWithPath: config.repoRoot)
      process.arguments = [
        "--filter",
        "@patrickjs/port-manager-cli",
        "exec",
        "port-manager"
      ] + arguments

      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr

      try process.run()
      let outputTask = Task<Data, Never> {
        stdout.fileHandleForReading.readDataToEndOfFile()
      }
      let errorTask = Task<Data, Never> {
        stderr.fileHandleForReading.readDataToEndOfFile()
      }

      process.waitUntilExit()

      let output = await outputTask.value
      let errorData = await errorTask.value

      guard process.terminationStatus == 0 else {
        let stderrMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutMessage = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderrMessage?.isEmpty == false
          ? stderrMessage!
          : stdoutMessage ?? "port-manager exited with \(process.terminationStatus)"
        throw PortManagerCLIError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
      }

      return output
    }.value
  }

  private func listeningPort(from entry: CLIPortEntry) -> ListeningPort {
    let bind = PortBind(
      id: "\(entry.owner.pid)-\(entry.protocol)-\(entry.host)-\(entry.port)",
      host: entry.host,
      port: entry.port,
      proto: entry.protocol,
      commonPort: entry.commonPort,
      ownerPid: entry.owner.pid,
      ownerName: entry.owner.name
    )

    return ListeningPort(
      id: bind.id,
      pid: entry.owner.pid,
      status: PortStatus(rawValue: entry.status ?? "listening") ?? .listening,
      processName: entry.owner.name ?? "",
      user: entry.owner.user ?? "unknown",
      uid: entry.owner.uid,
      parentPid: entry.owner.parentPid,
      command: entry.owner.command,
      arguments: entry.owner.args,
      currentDirectory: entry.owner.cwd,
      launchOriginator: entry.owner.launchd.originator,
      binds: [bind],
      ownerCount: 1,
      entryCount: 1,
      groupReason: nil,
      displayGroup: .other,
      ownershipEvidence: entry.owner.ownership.evidence,
      ownershipSummaryOverride: entry.owner.ownership.summary,
      ownershipConfidenceOverride: OwnershipConfidence(rawValue: entry.owner.ownership.confidence.capitalized)
    )
  }

  private func listeningPort(from group: CLIPortGroup) -> ListeningPort {
    let primaryOwner = group.owners.first ?? group.entries.first?.owner
    let binds = group.bindings.map { binding in
      PortBind(
        id: "\(group.id)-\(binding.protocol)-\(binding.host)",
        host: binding.host,
        port: binding.port,
        proto: binding.protocol,
        commonPort: binding.commonPort ?? group.commonPort,
        ownerPid: binding.ownerPid,
        ownerName: binding.ownerName
      )
    }
    let evidence = uniqueEvidence([
      group.reason,
      group.bindings.map { binding in
        if let ownerName = binding.ownerName, let ownerPid = binding.ownerPid {
          return "\(binding.label) owned by \(ownerName) (PID \(ownerPid))"
        }
        return binding.label
      }.joined(separator: ", ")
    ] + group.entries.flatMap { $0.owner.ownership.evidence })

    return ListeningPort(
      id: group.id,
      pid: primaryOwner?.pid ?? 0,
      status: PortStatus(rawValue: group.status) ?? .listening,
      processName: group.title,
      user: group.owners.count == 1 ? primaryOwner?.user ?? "unknown" : "\(group.owners.count) owners",
      uid: group.owners.count == 1 ? primaryOwner?.uid : nil,
      parentPid: group.owners.count == 1 ? primaryOwner?.parentPid : nil,
      command: group.owners.count == 1 ? primaryOwner?.command : nil,
      arguments: group.owners.count == 1 ? primaryOwner?.args : nil,
      currentDirectory: group.owners.count == 1 ? primaryOwner?.cwd : nil,
      launchOriginator: group.owners.count == 1 ? primaryOwner?.launchd.originator : nil,
      binds: binds,
      ownerCount: group.owners.count,
      entryCount: group.entries.count,
      groupReason: group.reason,
      displayGroup: group.displayGroup,
      ownershipEvidence: evidence,
      ownershipSummaryOverride: group.reason,
      ownershipConfidenceOverride: OwnershipConfidence(rawValue: primaryOwner?.ownership.confidence.capitalized ?? "")
    )
  }

  private func uniqueEvidence(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { value in
      guard !value.isEmpty, !seen.contains(value) else { return false }
      seen.insert(value)
      return true
    }
  }
}

struct PortManagerAppConfig: Decodable {
  let repoRoot: String
  let pnpmPath: String

  static func load() -> PortManagerAppConfig {
    guard let url = Bundle.main.url(forResource: "PortManagerConfig", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let config = try? JSONDecoder().decode(PortManagerAppConfig.self, from: data)
    else {
      return PortManagerAppConfig(
        repoRoot: FileManager.default.currentDirectoryPath,
        pnpmPath: "/opt/homebrew/bin/pnpm"
      )
    }

    return config
  }
}

enum PortManagerCLIError: LocalizedError {
  case commandFailed(String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let message):
      return message
    }
  }
}

private struct CLIEnvelope<Result: Decodable>: Decodable {
  let ok: Bool
  let result: Result
  let error: CLIErrorPayload?
}

private struct CLIErrorPayload: Decodable {
  let message: String
}

private struct CLIListResult: Decodable {
  let ports: [CLIPortEntry]
  let portGroups: [CLIPortGroup]?
}

private struct CLIPortGroup: Decodable {
  let id: String
  let port: Int
  let status: String
  let protocols: [String]
  let title: String
  let reason: String
  let commonPort: CommonPort?
  let displayGroup: PortDisplayGroup
  let owners: [CLIOwner]
  let bindings: [CLIGroupBinding]
  let entries: [CLIPortEntry]
}

private struct CLIGroupBinding: Decodable {
  let host: String
  let port: Int
  let `protocol`: String
  let label: String
  let ownerPid: Int?
  let ownerName: String?
  let status: String?
  let commonPort: CommonPort?
}

private struct CLIPortEntry: Decodable {
  let port: Int
  let host: String
  let `protocol`: String
  let status: String?
  let owner: CLIOwner
  let commonPort: CommonPort?
}

private struct CLIOwner: Decodable {
  let pid: Int
  let name: String?
  let user: String?
  let uid: Int?
  let parentPid: Int?
  let command: String?
  let args: String?
  let cwd: String?
  let launchd: CLILaunchd
  let ownership: CLIOwnership
}

private struct CLILaunchd: Decodable {
  let originator: String?
}

private struct CLIOwnership: Decodable {
  let confidence: String
  let summary: String
  let evidence: [String]
}

struct KillPortResult: Decodable {
  let ok: Bool
  let killed: [KilledProcess]
  let failed: [KillFailure]
}

struct KilledProcess: Decodable {
  let pid: Int
  let name: String?
  let signal: String
}

struct KillFailure: Decodable {
  let pid: Int
  let name: String?
  let code: String
  let message: String
}
