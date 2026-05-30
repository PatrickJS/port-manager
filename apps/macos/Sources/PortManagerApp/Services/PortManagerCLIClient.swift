import Foundation

protocol PortManagerCLIClientProtocol: Sendable {
  var activeScannerCommand: String { get }
  func listPorts() async throws -> [ListeningPort]
  func killPort(_ port: ListeningPort) async throws -> KillPortResult
}

struct PortManagerCLIClient: PortManagerCLIClientProtocol, Sendable {
  private let config: PortManagerAppConfig
  private let timeoutSeconds: TimeInterval

  init(config: PortManagerAppConfig = .load(), timeoutSeconds: TimeInterval = 8) {
    self.config = config
    self.timeoutSeconds = timeoutSeconds
  }

  var activeScannerCommand: String {
    commandAttempts.first?.description ?? "No scanner command available"
  }

  func listPorts() async throws -> [ListeningPort] {
    let data = try await runPortManager(arguments: ["list", "--json"])
    let envelope = try JSONDecoder().decode(CLIEnvelope<CLIListResult>.self, from: data)
    guard envelope.ok else {
      throw PortManagerCLIError.commandFailed(
        code: envelope.error?.code,
        message: envelope.error?.message ?? "port-manager list failed"
      )
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
      throw PortManagerCLIError.commandFailed(code: nil, message: "Selected process has no port binding")
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
      throw PortManagerCLIError.commandFailed(
        code: envelope.error?.code,
        message: envelope.error?.message ?? "port-manager kill failed"
      )
    }

    return envelope.result
  }

  private func runPortManager(arguments: [String]) async throws -> Data {
    var lastError: Error?
    for command in commandAttempts {
      do {
        return try await run(command: command, arguments: arguments)
      } catch let error as PortManagerCLIError {
        throw error
      } catch {
        lastError = error
      }
    }
    throw lastError ?? PortManagerCLIError.commandFailed(code: nil, message: "No Port Manager scanner command is available")
  }

  private var commandAttempts: [PortManagerCommand] {
    var commands: [PortManagerCommand] = []
    let fileManager = FileManager.default

    if let nodePath = config.nodePath,
       let cliEntrypointPath = config.cliEntrypointPath,
       fileManager.isExecutableFile(atPath: nodePath),
       fileManager.fileExists(atPath: cliEntrypointPath) {
      commands.append(
        PortManagerCommand(
          executablePath: nodePath,
          prefixArguments: [cliEntrypointPath],
          description: "node \(cliEntrypointPath)"
        )
      )
    }

    if fileManager.isExecutableFile(atPath: config.pnpmPath) {
      commands.append(
        PortManagerCommand(
          executablePath: config.pnpmPath,
          prefixArguments: [
            "--filter",
            "@patrickjs/port-manager-cli",
            "exec",
            "port-manager"
          ],
          description: "pnpm --filter @patrickjs/port-manager-cli exec port-manager"
        )
      )
    }

    return commands
  }

  private func run(command: PortManagerCommand, arguments: [String]) async throws -> Data {
    try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: command.executablePath)
      process.currentDirectoryURL = URL(fileURLWithPath: config.repoRoot)
      process.arguments = command.prefixArguments + arguments
      process.environment = config.processEnvironment

      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      let timeoutState = ProcessTimeoutState()

      try process.run()
      let timeoutTask = Task {
        try? await Task.sleep(for: .seconds(timeoutSeconds))
        if process.isRunning {
          timeoutState.markTimedOut()
          process.terminate()
        }
      }
      let outputTask = Task<Data, Never> {
        stdout.fileHandleForReading.readDataToEndOfFile()
      }
      let errorTask = Task<Data, Never> {
        stderr.fileHandleForReading.readDataToEndOfFile()
      }

      process.waitUntilExit()
      timeoutTask.cancel()

      let output = await outputTask.value
      let errorData = await errorTask.value

      if timeoutState.didTimeOut {
        throw PortManagerCLIError.commandFailed(
          code: "PORT_MANAGER_TIMEOUT",
          message: "Port scan timed out after \(Int(timeoutSeconds)) seconds while running \(command.description)"
        )
      }

      guard process.terminationStatus == 0 else {
        throw PortManagerCLIError.fromProcessOutput(
          stdout: output,
          stderr: errorData,
          fallback: "port-manager exited with \(process.terminationStatus)"
        )
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

struct PortManagerAppConfig: Decodable, Sendable {
  let repoRoot: String
  let pnpmPath: String
  let nodePath: String?
  let cliEntrypointPath: String?
  let pathEnvironment: String?

  var processEnvironment: [String: String] {
    var environment = ProcessInfo.processInfo.environment
    if let pathEnvironment, !pathEnvironment.isEmpty {
      environment["PATH"] = pathEnvironment
    } else if environment["PATH"] == nil {
      environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }
    if environment["HOME"] == nil {
      environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
    }
    return environment
  }

  static func load() -> PortManagerAppConfig {
    guard let url = Bundle.main.url(forResource: "PortManagerConfig", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let config = try? JSONDecoder().decode(PortManagerAppConfig.self, from: data)
    else {
      return PortManagerAppConfig(
        repoRoot: FileManager.default.currentDirectoryPath,
        pnpmPath: "/opt/homebrew/bin/pnpm",
        nodePath: "/opt/homebrew/bin/node",
        cliEntrypointPath: nil,
        pathEnvironment: "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      )
    }

    return config
  }
}

private struct PortManagerCommand: Sendable {
  let executablePath: String
  let prefixArguments: [String]
  let description: String
}

private final class ProcessTimeoutState: @unchecked Sendable {
  private let lock = NSLock()
  private var timedOut = false

  var didTimeOut: Bool {
    lock.withLock { timedOut }
  }

  func markTimedOut() {
    lock.withLock {
      timedOut = true
    }
  }
}

enum PortManagerCLIError: LocalizedError {
  case commandFailed(code: String?, message: String)

  static func fromProcessOutput(stdout: Data, stderr: Data, fallback: String) -> PortManagerCLIError {
    let stderrMessage = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let stdoutMessage = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawMessage = stderrMessage?.isEmpty == false
      ? stderrMessage!
      : stdoutMessage ?? fallback

    if let envelope = decodeErrorEnvelope(from: stderr) ?? decodeErrorEnvelope(from: stdout),
       let error = envelope.error {
      return .commandFailed(code: error.code, message: error.message)
    }

    return .commandFailed(code: nil, message: rawMessage.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  var code: String? {
    switch self {
    case .commandFailed(let code, _):
      return code
    }
  }

  var shouldRefreshPorts: Bool {
    code == "PORT_MANAGER_NO_OWNER"
  }

  var errorDescription: String? {
    switch self {
    case .commandFailed(let code, let message):
      if code == "PORT_MANAGER_NO_OWNER" {
        return "\(message). The port list may be stale, so Port Manager refreshed it."
      }
      return message
    }
  }

  private static func decodeErrorEnvelope(from data: Data) -> CLIErrorEnvelope? {
    guard !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
  }
}

private struct CLIEnvelope<Result: Decodable>: Decodable {
  let ok: Bool
  let result: Result
  let error: CLIErrorPayload?
}

private struct CLIErrorPayload: Decodable {
  let code: String?
  let message: String
}

private struct CLIErrorEnvelope: Decodable {
  let ok: Bool?
  let error: CLIErrorPayload?
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
