import Foundation
import Observation

struct PortInspection: Codable, Hashable {
  let key: String
  let title: String
  let generatedAt: Date
  let summary: String
  let details: [String]
  let basis: [String]
  let ports: [Int]
  let sources: [PortInspectionSource]?
  let warnings: [PortInspectionWarning]?
}

struct PortInspectionSource: Codable, Hashable, Identifiable {
  var id: String { url }
  let title: String
  let url: String
  let snippet: String?
}

struct PortInspectionWarning: Codable, Hashable, Identifiable {
  var id: String { message }
  let severity: String
  let message: String
}

@MainActor
@Observable
final class PortInspectionStore {
  var inspections: [String: PortInspection] = [:]
  var inspectingKeys: Set<String> = []

  private let defaultsKey = "PortManagerSavedInspections"

  init() {
    load()
  }

  func inspection(for port: ListeningPort, rules: [PortGroupingRule]) -> PortInspection? {
    inspections[portClusterKey(for: port, rules: rules)]
  }

  func isInspecting(_ port: ListeningPort, rules: [PortGroupingRule]) -> Bool {
    inspectingKeys.contains(portClusterKey(for: port, rules: rules))
  }

  func inspect(port: ListeningPort, allPorts: [ListeningPort], rules: [PortGroupingRule]) async {
    let key = portClusterKey(for: port, rules: rules)
    inspectingKeys.insert(key)
    defer { inspectingKeys.remove(key) }

    let inspection = await PortInspector.inspect(port: port, allPorts: allPorts, rules: rules)
    inspections[key] = inspection
    save()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode([String: PortInspection].self, from: data)
    else {
      return
    }
    inspections = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(inspections) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}

enum PortInspector {
  static func inspect(
    port: ListeningPort,
    allPorts: [ListeningPort],
    rules: [PortGroupingRule] = PortGroupingRule.defaults
  ) async -> PortInspection {
    let key = portClusterKey(for: port, rules: rules)
    let title = portClusterTitle(for: port, rules: rules)
    let relatedPorts = allPorts
      .filter { portClusterKey(for: $0, rules: rules) == key }
      .sorted { ($0.primaryPort ?? 0) < ($1.primaryPort ?? 0) }
    let portNumbers = relatedPorts.compactMap(\.primaryPort)
    let portList = portNumbers.map(String.init).joined(separator: ", ")
    let observedPorts = portList.isEmpty ? "unknown" : portList
    let portWord = pluralize("port", relatedPorts.count)
    let lowercasedTitle = title.lowercased()
    let publicBindings = relatedPorts.flatMap(\.binds).filter { bind in
      bind.host == "*" || bind.host == "0.0.0.0" || bind.host == "::"
    }
    let warnings = PortExpectationChecker.warnings(for: relatedPorts, title: title)

    let summary: String
    var details: [String]
    var basis = [
      "Inspected local lsof/ps ownership evidence and current bindings.",
    ]

    if lowercasedTitle == "cursor" || lowercasedTitle.hasPrefix("cursor helper") {
      summary = "Cursor has \(relatedPorts.count) helper-owned listening \(portWord) on this Mac. Several Cursor Helper processes are expected for a VS Code/Electron-family editor, especially with AI, extension, and workspace services active."
      details = [
        "Ports observed: \(observedPorts).",
        "There is no fixed universal normal count; the useful signal is whether the helpers are tied to Cursor, mostly localhost-bound, and disappear when Cursor fully quits.",
        "Inspect more closely if a helper binds a public interface, burns CPU, survives after Cursor quits, or appears from an unexpected app path.",
      ]
      basis.append("Electron apps use a Chromium-style multi-process model with helper processes.")
      basis.append("VS Code-family editors run extensions in extension hosts; helper count scales with extensions, windows, and workspace activity.")
    } else if lowercasedTitle == "ollama" {
      summary = "Ollama appears as one app cluster with \(relatedPorts.count) listening \(portWord). Seeing both `ollama` and `Ollama` usually means the CLI/server process and the desktop app/helper are both present."
      details = [
        "Ports observed: \(observedPorts).",
        "Port 11434 is the common local Ollama API port. Additional high ports can be app/helper listeners and should be checked by owner path and binding scope.",
        "Localhost-only bindings are generally expected for local model tooling; public bindings deserve review.",
      ]
    } else if lowercasedTitle == "tailscale" || lowercasedTitle.contains("ipnextension") {
      summary = "This looks like Tailscale's macOS network extension. It can own HTTPS or high-numbered listeners when Tailscale Serve, Funnel, or related tunnel features are active."
      details = [
        "Ports observed: \(observedPorts).",
        "Public `*` bindings can be intentional for tunnel/serve features, but should match your Tailscale configuration.",
      ]
    } else if ["raycast", "reflect", "spotify", "discord", "discord helper", "github desktop", "github desktop helper"].contains(lowercasedTitle) {
      summary = "\(title) owns \(relatedPorts.count) listening \(portWord). This is a desktop app/helper cluster; these are usually local coordination or embedded app services."
      details = [
        "Ports observed: \(observedPorts).",
        "Review if the binding is public, the app is not running, or the command path does not match the expected application.",
      ]
      basis.append("Desktop apps commonly use helper/background processes for local coordination.")
    } else if port.displayGroup.id == "os-apple" || port.displayGroup.id == "system" {
      summary = "\(title) is categorized as OS / Apple and is usually safe to ignore unless the binding or owner path looks unexpected."
      details = [
        "Ports observed: \(observedPorts).",
        "These rows are kept collapsed by default to reduce noise.",
      ]
    } else {
      summary = "\(title) owns \(relatedPorts.count) listening \(portWord) in the \(port.displayGroup.name) group."
      details = [
        "Ports observed: \(observedPorts).",
        "Use the command path, working directory, owner, and binding scope to decide whether it belongs to the current project or app.",
      ]
    }

    if !publicBindings.isEmpty {
      details.append("This cluster has \(publicBindings.count) public binding \(publicBindings.map { "\($0.host):\($0.port)" }.joined(separator: ", ")); verify that is intentional.")
    }

    if !warnings.isEmpty {
      details.insert("Warning: \(warnings.map(\.message).joined(separator: " "))", at: 0)
    }

    let onlineResearch = await OnlinePortResearchService.research(title: title, warnings: warnings)
    if !onlineResearch.sources.isEmpty {
      basis.append("Online research used app/category search terms only; local paths, arguments, and working directories were not sent.")
      if let summary = onlineResearch.summary {
        details.append(summary)
      }
    }

    return PortInspection(
      key: key,
      title: title,
      generatedAt: Date(),
      summary: summary,
      details: details,
      basis: basis,
      ports: portNumbers,
      sources: onlineResearch.sources,
      warnings: warnings
    )
  }

  private static func pluralize(_ word: String, _ count: Int) -> String {
    count == 1 ? word : "\(word)s"
  }
}

enum PortExpectationChecker {
  static func warnings(for ports: [ListeningPort], title: String) -> [PortInspectionWarning] {
    ports.flatMap { warnings(for: $0, title: title) }
  }

  private static func warnings(for port: ListeningPort, title: String) -> [PortInspectionWarning] {
    var warnings: [PortInspectionWarning] = []
    let lowercasedTitle = title.lowercased()
    let publicBindings = port.binds.filter { ["*", "0.0.0.0", "::"].contains($0.host) }
    let command = port.command?.lowercased() ?? ""
    let origin = port.launchOriginator?.lowercased() ?? ""

    if port.displayGroup.id == "os-apple" || title == "ControlCenter" || title == "rapportd" {
      if !command.hasPrefix("/system/") && !origin.hasPrefix("/system/") && !command.contains("/system/library/") {
        warnings.append(PortInspectionWarning(severity: "warning", message: "\(title) is categorized as OS / Apple, but its executable path is not under /System."))
      }
    }

    if lowercasedTitle == "ollama" {
      for bind in publicBindings {
        warnings.append(PortInspectionWarning(severity: "warning", message: "Ollama is binding \(bind.host):\(bind.port); local model APIs are usually expected to stay localhost-only unless you intentionally exposed them."))
      }
    }

    if lowercasedTitle == "cursor" {
      for bind in publicBindings {
        warnings.append(PortInspectionWarning(severity: "warning", message: "Cursor helper port \(bind.host):\(bind.port) is public; helper services are usually expected to be local-only."))
      }
    }

    if lowercasedTitle == "tailscale" {
      let hasServeLikePort = port.binds.contains { [443, 8443].contains($0.port) || $0.port >= 49152 }
      if !hasServeLikePort {
        warnings.append(PortInspectionWarning(severity: "notice", message: "Tailscale is using an uncommon listener for this app cluster; compare it with your Serve or Funnel configuration."))
      }
    }

    return warnings
  }
}
