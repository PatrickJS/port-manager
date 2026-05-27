import Foundation
import Observation

enum PortGroupingMatchMode: String, CaseIterable, Codable, Identifiable {
  case exact
  case prefix
  case contains

  var id: String { rawValue }

  var title: String {
    switch self {
    case .exact:
      return "Exact"
    case .prefix:
      return "Prefix"
    case .contains:
      return "Contains"
    }
  }
}

struct PortGroupingRule: Identifiable, Codable, Hashable {
  var id: String
  var isEnabled: Bool
  var match: String
  var matchMode: PortGroupingMatchMode
  var title: String
  var displayGroupID: String

  static let defaults: [PortGroupingRule] = [
    PortGroupingRule(id: "ollama", isEnabled: true, match: "ollama", matchMode: .exact, title: "Ollama", displayGroupID: "ai"),
    PortGroupingRule(id: "cursor-helper", isEnabled: true, match: "cursor helper", matchMode: .prefix, title: "Cursor", displayGroupID: "ai"),
    PortGroupingRule(id: "cursor", isEnabled: true, match: "cursor", matchMode: .exact, title: "Cursor", displayGroupID: "ai"),
    PortGroupingRule(id: "github-desktop", isEnabled: true, match: "github desktop helper", matchMode: .prefix, title: "GitHub Desktop", displayGroupID: "apps"),
    PortGroupingRule(id: "discord", isEnabled: true, match: "discord helper", matchMode: .prefix, title: "Discord", displayGroupID: "apps"),
    PortGroupingRule(id: "raycast", isEnabled: true, match: "raycast", matchMode: .exact, title: "Raycast", displayGroupID: "apps"),
    PortGroupingRule(id: "reflect", isEnabled: true, match: "reflect", matchMode: .exact, title: "Reflect", displayGroupID: "apps"),
    PortGroupingRule(id: "spotify", isEnabled: true, match: "spotify", matchMode: .exact, title: "Spotify", displayGroupID: "apps"),
    PortGroupingRule(id: "goalbuddy", isEnabled: true, match: "goalbuddy", matchMode: .contains, title: "GoalBuddy", displayGroupID: "web-dev"),
    PortGroupingRule(id: "tailscale-ipn", isEnabled: true, match: "ipnextension", matchMode: .exact, title: "Tailscale", displayGroupID: "tunnels"),
    PortGroupingRule(id: "cloudflared", isEnabled: true, match: "cloudflared", matchMode: .exact, title: "Cloudflare Tunnel", displayGroupID: "tunnels"),
    PortGroupingRule(id: "ngrok", isEnabled: true, match: "ngrok", matchMode: .exact, title: "ngrok", displayGroupID: "tunnels"),
  ]

  func matches(_ value: String) -> Bool {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let needle = match.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !candidate.isEmpty, !needle.isEmpty else { return false }

    switch matchMode {
    case .exact:
      return candidate == needle
    case .prefix:
      return candidate.hasPrefix(needle)
    case .contains:
      return candidate.contains(needle)
    }
  }
}

enum PortGroupingCategories {
  static let defaults: [PortDisplayGroup] = [
    PortDisplayGroup(id: "web-dev", name: "Web Dev", rank: 10),
    PortDisplayGroup(id: "databases", name: "Databases", rank: 20),
    PortDisplayGroup(id: "ai", name: "AI", rank: 30),
    PortDisplayGroup(id: "tunnels", name: "Tunnels", rank: 40),
    PortDisplayGroup(id: "apps", name: "Apps", rank: 80),
    PortDisplayGroup.other,
    PortDisplayGroup(id: "os-apple", name: "OS / Apple", rank: 120),
  ]

  static func displayGroup(for id: String) -> PortDisplayGroup? {
    defaults.first { $0.id == id }
  }
}

@MainActor
@Observable
final class PortGroupingRulesStore {
  var rules: [PortGroupingRule] = [] {
    didSet {
      guard isLoaded else { return }
      save()
    }
  }

  private let defaultsKey = "PortManagerGroupingRules"
  private var isLoaded = false

  init() {
    reload()
  }

  func reload() {
    isLoaded = false
    if let data = UserDefaults.standard.data(forKey: defaultsKey),
       let decoded = try? JSONDecoder().decode([PortGroupingRule].self, from: data) {
      rules = decoded
    } else {
      rules = PortGroupingRule.defaults
    }
    isLoaded = true
  }

  func addRule() {
    rules.append(
      PortGroupingRule(
        id: UUID().uuidString,
        isEnabled: true,
        match: "",
        matchMode: .contains,
        title: "",
        displayGroupID: "other"
      )
    )
  }

  func deleteRules(at offsets: IndexSet) {
    rules.remove(atOffsets: offsets)
  }

  func moveRule(from source: IndexSet, to destination: Int) {
    rules.move(fromOffsets: source, toOffset: destination)
  }

  func resetDefaults() {
    rules = PortGroupingRule.defaults
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
    NotificationCenter.default.post(name: .groupingRulesChanged, object: nil)
  }
}

extension Notification.Name {
  static let groupingRulesChanged = Notification.Name("PortManagerGroupingRulesChanged")
}
