import Foundation

enum LocalAIInspectionService {
  struct ProviderCheck {
    let message: String
    let ollamaModels: [String]
    let recommendedOllamaModel: String?
  }

  static func providerStatus(settings: LocalAISettings) async -> String {
    await providerCheck(settings: settings).message
  }

  static func providerCheck(settings: LocalAISettings) async -> ProviderCheck {
    async let ollama = ollamaStatusAndModels(settings: settings)
    async let codex = codexStatus(settings: settings)
    let ollamaResult = await ollama
    return ProviderCheck(
      message: [ollamaResult.message, await codex].joined(separator: "\n"),
      ollamaModels: ollamaResult.models,
      recommendedOllamaModel: ollamaResult.recommendedModel
    )
  }

  static func enrich(
    title: String,
    ports: [ListeningPort],
    warnings: [PortInspectionWarning],
    onlineResearch: OnlinePortResearch,
    settings: LocalAISettings
  ) async -> PortInspectionAI? {
    switch settings.providerMode {
    case .off:
      return nil
    case .ollama:
      return await ollamaEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings)
    case .codexCLI:
      return await codexEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings)
    case .auto:
      if settings.preferCodexInAuto {
        if let codex = await codexEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings) {
          return codex
        }
        return await ollamaEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings)
      }
      if let ollama = await ollamaEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings) {
        return ollama
      }
      return await codexEnrichment(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings)
    }
  }

  private static func ollamaStatusAndModels(settings: LocalAISettings) async -> (message: String, models: [String], recommendedModel: String?) {
    let models = await ollamaModels(baseURL: settings.ollamaBaseURL)
    let recommended = recommendedOllamaModel(from: models, configuredModel: settings.ollamaModel)
    guard let recommended else {
      if models.isEmpty {
        return ("Ollama: unavailable at \(settings.ollamaBaseURL)", models, nil)
      }
      return ("Ollama: available, but no chat model was found", models, nil)
    }
    return ("Ollama: available (\(recommended))", models, recommended)
  }

  private static func codexStatus(settings: LocalAISettings) async -> String {
    do {
      let output = try await runProcess(command: settings.codexCommand, arguments: ["--version"], timeoutSeconds: 5)
      let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
      return version.isEmpty ? "Codex CLI: available" : "Codex CLI: \(version)"
    } catch {
      return "Codex CLI: unavailable"
    }
  }

  private static func ollamaEnrichment(
    title: String,
    ports: [ListeningPort],
    warnings: [PortInspectionWarning],
    onlineResearch: OnlinePortResearch,
    settings: LocalAISettings
  ) async -> PortInspectionAI? {
    guard let model = await resolveOllamaModel(settings: settings),
          let url = apiURL(baseURL: settings.ollamaBaseURL, path: "api/generate")
    else {
      return nil
    }

    let body = OllamaGenerateRequest(
      model: model,
      prompt: prompt(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings),
      stream: false,
      options: ["temperature": 0.2]
    )

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(body)

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let decoded = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
      else {
        return nil
      }

      let summary = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !summary.isEmpty else { return nil }
      return PortInspectionAI(provider: "Ollama", model: model, generatedAt: Date(), summary: summary)
    } catch {
      return nil
    }
  }

  private static func codexEnrichment(
    title: String,
    ports: [ListeningPort],
    warnings: [PortInspectionWarning],
    onlineResearch: OnlinePortResearch,
    settings: LocalAISettings
  ) async -> PortInspectionAI? {
    let model = await resolveOllamaModel(settings: settings)
    let outputURL = FileManager.default.temporaryDirectory
      .appending(path: "port-manager-codex-\(UUID().uuidString).txt")
    defer {
      try? FileManager.default.removeItem(at: outputURL)
    }

    var arguments = [
      "exec",
      "--oss",
      "--local-provider",
      "ollama"
    ]
    if let model {
      arguments += ["-m", model]
    }
    arguments += [
      "-s",
      "read-only",
      "--cd",
      NSTemporaryDirectory(),
      "--skip-git-repo-check",
      "--ephemeral",
      "--ignore-rules",
      "--ignore-user-config",
      "-o",
      outputURL.path,
      prompt(title: title, ports: ports, warnings: warnings, onlineResearch: onlineResearch, settings: settings)
    ]

    do {
      _ = try await runProcess(
        command: settings.codexCommand,
        arguments: arguments,
        timeoutSeconds: 75
      )
      let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
      let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !summary.isEmpty else { return nil }
      return PortInspectionAI(provider: "Codex CLI", model: model, generatedAt: Date(), summary: summary)
    } catch {
      return nil
    }
  }

  private static func resolveOllamaModel(settings: LocalAISettings) async -> String? {
    recommendedOllamaModel(
      from: await ollamaModels(baseURL: settings.ollamaBaseURL),
      configuredModel: settings.ollamaModel
    )
  }

  static func recommendedOllamaModel(from models: [String], configuredModel: String) -> String? {
    let generativeModels = models.filter(isGenerativeOllamaModel)
    guard !generativeModels.isEmpty else { return nil }
    let configuredModel = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !configuredModel.isEmpty, generativeModels.contains(configuredModel) {
      return configuredModel
    }

    for preferred in ["gpt-oss", "qwen3-coder", "llama3", "mistral", "magicoder", "orca"] {
      if let model = generativeModels.first(where: { $0.localizedCaseInsensitiveContains(preferred) }) {
        return model
      }
    }
    return generativeModels.first
  }

  static func isGenerativeOllamaModel(_ model: String) -> Bool {
    !model.localizedCaseInsensitiveContains("embed")
  }

  private static func ollamaModels(baseURL: String) async -> [String] {
    guard let url = apiURL(baseURL: baseURL, path: "api/tags") else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 4

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data)
      else {
        return []
      }
      return decoded.models.map(\.name)
    } catch {
      return []
    }
  }

  private static func prompt(
    title: String,
    ports: [ListeningPort],
    warnings: [PortInspectionWarning],
    onlineResearch: OnlinePortResearch,
    settings: LocalAISettings
  ) -> String {
    let portLines = ports.map { port in
      let bindings = port.binds.map { "\($0.host):\($0.port)/\($0.proto)" }.joined(separator: ", ")
      let command = sanitizedCommand(port.command)
      return "- \(port.title), PID \(port.pid), bindings \(bindings), command \(command)"
    }.joined(separator: "\n")
    let warningLines = warnings.isEmpty
      ? "- none"
      : warnings.map { "- \($0.message)" }.joined(separator: "\n")
    let sourceLines = onlineResearch.sources.isEmpty
      ? "- none"
      : onlineResearch.sources.map { source in
        "- \(source.title): \(source.snippet ?? source.url)"
      }.joined(separator: "\n")

    let template = settings.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? LocalAISettings.defaultPromptTemplate
      : settings.promptTemplate
    return template
      .replacingOccurrences(of: "{cluster}", with: title)
      .replacingOccurrences(of: "{localEvidence}", with: portLines)
      .replacingOccurrences(of: "{warnings}", with: warningLines)
      .replacingOccurrences(of: "{onlineSources}", with: sourceLines)
  }

  private static func sanitizedCommand(_ command: String?) -> String {
    guard let command, !command.isEmpty else { return "unknown" }
    if command.hasPrefix("/Applications/") || command.hasPrefix("/System/") || command.hasPrefix("/opt/homebrew/") || command.hasPrefix("/usr/") {
      return command
    }
    return URL(fileURLWithPath: command).lastPathComponent
  }

  private static func apiURL(baseURL: String, path: String) -> URL? {
    guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return base.appending(path: path)
  }

  private static func runProcess(command: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String {
    try await Task.detached {
      let process = Process()
      if command.contains("/") {
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
      } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
      }
      process.environment = PortManagerAppConfig.load().processEnvironment

      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      try process.run()
      let stdoutTask = Task<Data, Never> {
        stdout.fileHandleForReading.readDataToEndOfFile()
      }
      let stderrTask = Task<Data, Never> {
        stderr.fileHandleForReading.readDataToEndOfFile()
      }

      let deadline = Date().addingTimeInterval(timeoutSeconds)
      while process.isRunning && Date() < deadline {
        try await Task.sleep(nanoseconds: 50_000_000)
      }
      if process.isRunning {
        process.terminate()
        throw LocalAIError.timedOut
      }

      let output = await stdoutTask.value
      let errorOutput = await stderrTask.value
      guard process.terminationStatus == 0 else {
        let message = String(data: errorOutput, encoding: .utf8) ?? "process failed"
        throw LocalAIError.processFailed(message)
      }
      return String(data: output, encoding: .utf8) ?? ""
    }.value
  }
}

private struct OllamaTagsResponse: Decodable {
  let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
  let name: String
}

private struct OllamaGenerateRequest: Encodable {
  let model: String
  let prompt: String
  let stream: Bool
  let options: [String: Double]
}

private struct OllamaGenerateResponse: Decodable {
  let response: String
}

private enum LocalAIError: Error {
  case timedOut
  case processFailed(String)
}
