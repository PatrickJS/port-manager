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

    return envelope.result.ports.map { entry in
      let bind = PortBind(
        id: "\(entry.owner.pid)-\(entry.protocol)-\(entry.host)-\(entry.port)",
        host: entry.host,
        port: entry.port,
        proto: entry.protocol,
        commonPort: entry.commonPort
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
        ownershipEvidence: entry.owner.ownership.evidence,
        ownershipSummaryOverride: entry.owner.ownership.summary,
        ownershipConfidenceOverride: OwnershipConfidence(rawValue: entry.owner.ownership.confidence.capitalized)
      )
    }
  }

  func killPort(_ port: ListeningPort) async throws -> KillPortResult {
    guard let primaryPort = port.primaryPort else {
      throw PortManagerCLIError.commandFailed("Selected process has no port binding")
    }

    let data = try await runPortManager(arguments: [
      "kill",
      "\(primaryPort)",
      "--pid",
      "\(port.pid)",
      "--json"
    ])
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
      process.waitUntilExit()

      let output = stdout.fileHandleForReading.readDataToEndOfFile()
      let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

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
