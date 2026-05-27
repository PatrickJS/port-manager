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

func portClusters(for ports: [ListeningPort], namespace: String) -> [PortCluster] {
  var buckets: [String: (title: String, ports: [ListeningPort])] = [:]

  for port in ports {
    let title = portClusterTitle(for: port)
    let key = portClusterKey(for: port)
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

func portClusterTitle(for port: ListeningPort) -> String {
  let title = port.title.trimmingCharacters(in: .whitespacesAndNewlines)
  if !title.isEmpty {
    return normalizedPortClusterTitle(title)
  }
  if let commonName = port.binds.compactMap(\.commonPort?.name).first {
    return normalizedPortClusterTitle(commonName)
  }
  return "Unknown"
}

func portClusterKey(for port: ListeningPort) -> String {
  normalizedPortClusterKey(portClusterTitle(for: port))
}

private func normalizedPortClusterTitle(_ title: String) -> String {
  let lowercased = title.lowercased()
  if lowercased == "ollama" {
    return "Ollama"
  }
  if lowercased.hasPrefix("cursor helper") {
    return "Cursor Helper (Plugin)"
  }
  if lowercased.hasPrefix("github desktop helper") {
    return "GitHub Desktop Helper"
  }
  if lowercased.hasPrefix("discord helper") {
    return "Discord Helper"
  }
  if lowercased == "raycast" {
    return "Raycast"
  }
  if lowercased == "reflect" {
    return "Reflect"
  }
  if lowercased == "spotify" {
    return "Spotify"
  }
  return title
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
