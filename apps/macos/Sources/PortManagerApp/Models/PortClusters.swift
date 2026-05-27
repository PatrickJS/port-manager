import Foundation

struct PortCluster: Identifiable, Hashable {
  let id: String
  let title: String
  let ports: [ListeningPort]

  var portCount: Int {
    ports.count
  }

  var isSinglePort: Bool {
    ports.count == 1
  }

  var firstPort: ListeningPort? {
    ports.first
  }

  var portList: String {
    ports
      .compactMap(\.primaryPort)
      .map(String.init)
      .joined(separator: ", ")
  }
}

func portClusters(
  for ports: [ListeningPort],
  namespace: String,
  rules: [PortGroupingRule] = PortGroupingRule.defaults
) -> [PortCluster] {
  var buckets: [String: (title: String, ports: [ListeningPort])] = [:]

  for port in ports {
    let title = portClusterTitle(for: port, rules: rules)
    let key = portClusterKey(for: port, rules: rules)
    var bucket = buckets[key] ?? (title: title, ports: [])
    bucket.ports.append(port)
    buckets[key] = bucket
  }

  return buckets
    .map { key, bucket in
      let sortedPorts = bucket.ports.sorted(by: sortClusterPorts)
      return PortCluster(
        id: "\(namespace)-\(key)",
        title: bucket.title,
        ports: sortedPorts
      )
    }
    .sorted { lhs, rhs in
      let leftPort = lhs.ports.first?.primaryPort ?? 0
      let rightPort = rhs.ports.first?.primaryPort ?? 0
      if leftPort != rightPort {
        return leftPort < rightPort
      }
      return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

func portClusterTitle(for port: ListeningPort, rules: [PortGroupingRule] = PortGroupingRule.defaults) -> String {
  let title = port.title.trimmingCharacters(in: .whitespacesAndNewlines)
  if !title.isEmpty {
    return normalizedPortClusterTitle(title, rules: rules)
  }
  if let commonName = port.binds.compactMap(\.commonPort?.name).first {
    return normalizedPortClusterTitle(commonName, rules: rules)
  }
  return "Unknown"
}

func portClusterKey(for port: ListeningPort, rules: [PortGroupingRule] = PortGroupingRule.defaults) -> String {
  normalizedPortClusterKey(portClusterTitle(for: port, rules: rules))
}

func normalizedPortClusterTitle(_ title: String, rules: [PortGroupingRule] = PortGroupingRule.defaults) -> String {
  if let rule = matchingGroupingRule(for: [title], rules: rules),
     !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return title
}

func configuredDisplayGroup(for port: ListeningPort, rules: [PortGroupingRule]) -> PortDisplayGroup {
  guard let rule = matchingGroupingRule(for: groupingCandidates(for: port), rules: rules),
        let displayGroup = PortGroupingCategories.displayGroup(for: rule.displayGroupID)
  else {
    return port.displayGroup
  }
  return displayGroup
}

func matchingGroupingRule(for candidates: [String], rules: [PortGroupingRule]) -> PortGroupingRule? {
  rules.first { rule in
    rule.isEnabled && candidates.contains { rule.matches($0) }
  }
}

private func groupingCandidates(for port: ListeningPort) -> [String] {
  [
    port.title,
    port.processName,
    port.command ?? "",
    port.arguments ?? "",
    port.currentDirectory ?? "",
    port.launchOriginator ?? "",
    port.binds.compactMap(\.commonPort?.name).joined(separator: " "),
    port.binds.compactMap(\.ownerName).joined(separator: " "),
  ]
}

private func normalizedPortClusterKey(_ title: String) -> String {
  title
    .lowercased()
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
    .joined(separator: "-")
}

private func sortClusterPorts(_ lhs: ListeningPort, _ rhs: ListeningPort) -> Bool {
  if lhs.primaryPort != rhs.primaryPort {
    return (lhs.primaryPort ?? 0) < (rhs.primaryPort ?? 0)
  }
  return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}
