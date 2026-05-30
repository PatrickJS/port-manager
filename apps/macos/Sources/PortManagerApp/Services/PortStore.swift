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
  var lastRefreshStarted: Date?
  var lastRefreshError: String?
  var lastRefreshDuration: TimeInterval?
  var activeScannerCommand: String

  private let cliClient: any PortManagerCLIClientProtocol
  private var activeRefresh: Task<Void, Never>?

  init(cliClient: any PortManagerCLIClientProtocol = PortManagerCLIClient()) {
    self.cliClient = cliClient
    activeScannerCommand = cliClient.activeScannerCommand
  }

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
        port.binds.compactMap(\.ownerName).joined(separator: " "),
        port.binds.compactMap(\.commonPort?.name).joined(separator: " ")
      ].joined(separator: " ").localizedLowercase
      return haystack.contains(query.localizedLowercase)
    }
  }

  var selectedPort: ListeningPort? {
    guard let selection else { return filteredPorts.first }
    return ports.first { $0.id == selection }
  }

  func refresh(force: Bool = false) async {
    if let activeRefresh {
      await activeRefresh.value
      return
    }

    let task = Task { [weak self] in
      guard let self else { return }
      await self.performRefresh()
    }
    activeRefresh = task
    await task.value
  }

  private func performRefresh() async {
    let started = Date()
    lastRefreshStarted = started
    lastRefreshDuration = nil
    lastRefreshError = nil
    activeScannerCommand = cliClient.activeScannerCommand
    isLoading = true
    errorMessage = nil
    defer {
      isLoading = false
      lastRefreshDuration = Date().timeIntervalSince(started)
      activeRefresh = nil
    }

    do {
      let scannedPorts = try await cliClient.listPorts()
      ports = scannedPorts
      lastUpdated = Date()
      if selection == nil || !scannedPorts.contains(where: { $0.id == selection }) {
        selection = scannedPorts.first?.id
      }
    } catch {
      let message = error.localizedDescription
      errorMessage = message
      lastRefreshError = message
    }
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
      let message = error.localizedDescription
      if let cliError = error as? PortManagerCLIError, cliError.shouldRefreshPorts {
        await refresh(force: true)
        statusMessage = message
      } else {
        errorMessage = message
      }
    }
    isKilling = false
  }
}
