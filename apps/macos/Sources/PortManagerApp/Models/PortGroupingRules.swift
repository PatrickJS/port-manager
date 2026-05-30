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

  static func displayGroup(for id: String, in groups: [PortDisplayGroup] = defaults) -> PortDisplayGroup? {
    groups.first { $0.id == id } ?? defaults.first { $0.id == id }
  }

  static func nextRank(in groups: [PortDisplayGroup]) -> Int {
    ((groups.map(\.rank).max() ?? 0) / 10 + 1) * 10
  }

  static func stableID(for name: String, existingIDs: Set<String>) -> String {
    let base = name
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "-")
    let fallback = base.isEmpty ? "custom-group" : base
    var candidate = fallback
    var suffix = 2
    while existingIDs.contains(candidate) {
      candidate = "\(fallback)-\(suffix)"
      suffix += 1
    }
    return candidate
  }
}

@MainActor
@Observable
final class PortGroupingRulesStore {
  var groups: [PortDisplayGroup] = [] {
    didSet {
      guard isLoaded else { return }
      saveGroups()
      repairRuleGroupReferences()
    }
  }

  var rules: [PortGroupingRule] = [] {
    didSet {
      guard isLoaded else { return }
      saveRules()
    }
  }

  private let rulesDefaultsKey = "PortManagerGroupingRules"
  private let groupsDefaultsKey = "PortManagerGroupingGroups"
  private var isLoaded = false

  init() {
    reload()
  }

  func reload() {
    isLoaded = false
    if let data = UserDefaults.standard.data(forKey: groupsDefaultsKey),
       let decoded = try? JSONDecoder().decode([PortDisplayGroup].self, from: data) {
      groups = sanitizedGroups(decoded)
    } else {
      groups = PortGroupingCategories.defaults
    }

    if let data = UserDefaults.standard.data(forKey: rulesDefaultsKey),
       let decoded = try? JSONDecoder().decode([PortGroupingRule].self, from: data) {
      rules = decoded
    } else {
      rules = PortGroupingRule.defaults
    }
    repairRuleGroupReferences()
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
        displayGroupID: defaultGroupID
      )
    )
  }

  func addGroup() {
    let id = PortGroupingCategories.stableID(
      for: "New Group",
      existingIDs: Set(groups.map(\.id))
    )
    groups.append(
      PortDisplayGroup(
        id: id,
        name: "New Group",
        rank: PortGroupingCategories.nextRank(in: groups)
      )
    )
  }

  func deleteGroup(at index: Int) {
    guard groups.indices.contains(index) else { return }
    guard groups[index].id != PortDisplayGroup.other.id else { return }
    let removed = groups.remove(at: index)
    let fallback = defaultGroupID
    rules = rules.map { rule in
      var updated = rule
      if updated.displayGroupID == removed.id {
        updated.displayGroupID = fallback
      }
      return updated
    }
  }

  func deleteRules(at offsets: IndexSet) {
    rules.remove(atOffsets: offsets)
  }

  func moveRule(from source: IndexSet, to destination: Int) {
    rules.move(fromOffsets: source, toOffset: destination)
  }

  func resetDefaults() {
    resetGroups()
    resetRules()
  }

  func resetGroups() {
    groups = PortGroupingCategories.defaults
  }

  func resetRules() {
    rules = PortGroupingRule.defaults
    repairRuleGroupReferences()
  }

  private var defaultGroupID: String {
    if groups.contains(where: { $0.id == PortDisplayGroup.other.id }) {
      return PortDisplayGroup.other.id
    }
    return groups.first?.id ?? PortDisplayGroup.other.id
  }

  private func repairRuleGroupReferences() {
    let groupIDs = Set(groups.map(\.id))
    rules = rules.map { rule in
      guard !groupIDs.contains(rule.displayGroupID) else { return rule }
      var repaired = rule
      repaired.displayGroupID = defaultGroupID
      return repaired
    }
  }

  private func sanitizedGroups(_ decoded: [PortDisplayGroup]) -> [PortDisplayGroup] {
    var seen = Set<String>()
    let sanitized = decoded.filter { group in
      let isValid = !group.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !seen.contains(group.id)
      if isValid {
        seen.insert(group.id)
      }
      return isValid
    }
    return sanitized.isEmpty ? PortGroupingCategories.defaults : sanitized
  }

  private func saveGroups() {
    guard let data = try? JSONEncoder().encode(groups) else { return }
    UserDefaults.standard.set(data, forKey: groupsDefaultsKey)
    NotificationCenter.default.post(name: .groupingRulesChanged, object: nil)
  }

  private func saveRules() {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: rulesDefaultsKey)
    NotificationCenter.default.post(name: .groupingRulesChanged, object: nil)
  }
}

extension Notification.Name {
  static let groupingRulesChanged = Notification.Name("PortManagerGroupingRulesChanged")
}
