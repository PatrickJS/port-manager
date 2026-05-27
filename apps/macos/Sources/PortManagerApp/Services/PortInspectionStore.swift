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

  func inspection(for port: ListeningPort) -> PortInspection? {
    inspections[portClusterKey(for: port)]
  }

  func isInspecting(_ port: ListeningPort) -> Bool {
    inspectingKeys.contains(portClusterKey(for: port))
  }

  func inspect(port: ListeningPort, allPorts: [ListeningPort]) async {
    let key = portClusterKey(for: port)
    inspectingKeys.insert(key)
    defer { inspectingKeys.remove(key) }

    let inspection = PortInspector.inspect(port: port, allPorts: allPorts)
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
  static func inspect(port: ListeningPort, allPorts: [ListeningPort]) -> PortInspection {
    let key = portClusterKey(for: port)
    let title = portClusterTitle(for: port)
    let relatedPorts = allPorts
      .filter { portClusterKey(for: $0) == key }
      .sorted { ($0.primaryPort ?? 0) < ($1.primaryPort ?? 0) }
    let portNumbers = relatedPorts.compactMap(\.primaryPort)
    let portList = portNumbers.map(String.init).joined(separator: ", ")
    let observedPorts = portList.isEmpty ? "unknown" : portList
    let portWord = pluralize("port", relatedPorts.count)
    let lowercasedTitle = title.lowercased()
    let publicBindings = relatedPorts.flatMap(\.binds).filter { bind in
      bind.host == "*" || bind.host == "0.0.0.0" || bind.host == "::"
    }

    let summary: String
    var details: [String]
    var basis = [
      "Inspected local lsof/ps ownership evidence and current bindings.",
    ]

    if lowercasedTitle.hasPrefix("cursor helper") {
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
    } else if lowercasedTitle.contains("ipnextension") {
      summary = "This looks like Tailscale's macOS network extension. It can own HTTPS or high-numbered listeners when Tailscale Serve, Funnel, or related tunnel features are active."
      details = [
        "Ports observed: \(observedPorts).",
        "Public `*` bindings can be intentional for tunnel/serve features, but should match your Tailscale configuration.",
      ]
    } else if ["raycast", "reflect", "spotify", "discord helper", "github desktop helper"].contains(lowercasedTitle) {
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

    return PortInspection(
      key: key,
      title: title,
      generatedAt: Date(),
      summary: summary,
      details: details,
      basis: basis,
      ports: portNumbers
    )
  }

  private static func pluralize(_ word: String, _ count: Int) -> String {
    count == 1 ? word : "\(word)s"
  }
}
