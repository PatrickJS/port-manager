import Foundation
import Observation

@MainActor
@Observable
final class PortStore {
  var ports: [ListeningPort] = []
  var selection: ListeningPort.ID?
  var searchText = ""
  var isLoading = false
  var isKilling = false
  var errorMessage: String?
  var statusMessage: String?
  var lastUpdated: Date?

  private let cliClient = PortManagerCLIClient()

  var filteredPorts: [ListeningPort] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return ports }

    return ports.filter { port in
      let haystack = [
        port.title,
        port.user,
        "\(port.pid)",
        port.command ?? "",
        port.arguments ?? "",
        port.binds.map { "\($0.host):\($0.port)" }.joined(separator: " "),
        port.binds.compactMap(\.commonPort?.name).joined(separator: " ")
      ].joined(separator: " ").localizedLowercase
      return haystack.contains(query.localizedLowercase)
    }
  }

  var selectedPort: ListeningPort? {
    guard let selection else { return filteredPorts.first }
    return ports.first { $0.id == selection }
  }

  func refresh() async {
    isLoading = true
    errorMessage = nil
    do {
      let scannedPorts = try await cliClient.listPorts()
      ports = scannedPorts
      lastUpdated = Date()
      if selection == nil || !scannedPorts.contains(where: { $0.id == selection }) {
        selection = scannedPorts.first?.id
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  func kill(_ port: ListeningPort) async {
    guard port.canKill else { return }

    isKilling = true
    errorMessage = nil
    statusMessage = nil
    do {
      let result = try await cliClient.killPort(port)
      let names = result.killed.map { process in
        process.name ?? "PID \(process.pid)"
      }.joined(separator: ", ")
      statusMessage = names.isEmpty ? "Kill signal sent" : "Killed \(names)"
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
    isKilling = false
  }
}
