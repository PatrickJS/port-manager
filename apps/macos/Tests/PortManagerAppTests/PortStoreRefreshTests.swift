import Foundation
import AppKit
import Testing
@testable import PortManagerApp

@MainActor
@Test func concurrentRefreshesShareOneScannerRunAndResetLoadingState() async {
  let client = CountingPortManagerClient(result: [
    listeningPort(
      processName: "node",
      command: "/opt/homebrew/bin/node",
      bind: PortBind(id: "node-41737", host: "127.0.0.1", port: 41737, proto: "TCP", commonPort: nil, ownerPid: 41737, ownerName: "node"),
      displayGroup: PortDisplayGroup(id: "web-dev", name: "Web Dev", rank: 10)
    )
  ])
  let store = PortStore(cliClient: client)

  async let first: Void = store.refresh(force: true)
  async let second: Void = store.refresh(force: true)
  _ = await (first, second)

  #expect(await client.listCallCount == 1)
  #expect(store.ports.compactMap(\.primaryPort) == [41737])
  #expect(!store.isLoading)
  #expect(store.lastUpdated != nil)
  #expect(store.lastRefreshError == nil)
  #expect(store.lastRefreshDuration != nil)
  #expect(store.activeScannerCommand == "test scanner")
}

@MainActor
@Test func staleOwnerKillRefreshesAndKeepsJsonOutOfUserFacingError() async {
  let stalePort = listeningPort(
    processName: "node",
    command: "/opt/homebrew/bin/node",
    bind: PortBind(id: "node-41737", host: "127.0.0.1", port: 41737, proto: "TCP", commonPort: nil, ownerPid: 41737, ownerName: "node"),
    displayGroup: PortDisplayGroup(id: "web-dev", name: "Web Dev", rank: 10)
  )
  let client = CountingPortManagerClient(
    result: [],
    killError: PortManagerCLIError.commandFailed(code: "PORT_MANAGER_NO_OWNER", message: "No process owner found for port 41737")
  )
  let store = PortStore(cliClient: client)
  store.ports = [stalePort]

  await store.kill(stalePort)

  #expect(await client.killCallCount == 1)
  #expect(await client.listCallCount == 1)
  #expect(store.ports.isEmpty)
  #expect(store.statusMessage == "No process owner found for port 41737. The port list may be stale, so Port Manager refreshed it.")
  #expect(store.errorMessage == nil)
  #expect(store.statusMessage?.contains("\"schemaVersion\"") == false)
  #expect(!store.isKilling)
}

@MainActor
@Test func refreshTimeoutErrorIsHumanReadableAndResetsLoadingState() async {
  let client = CountingPortManagerClient(
    result: [],
    listError: PortManagerCLIError.commandFailed(
      code: "PORT_MANAGER_TIMEOUT",
      message: "Port scan timed out after 1 seconds while running test scanner"
    )
  )
  let store = PortStore(cliClient: client)

  await store.refresh(force: true)

  #expect(await client.listCallCount == 1)
  #expect(!store.isLoading)
  #expect(store.errorMessage == "Port scan timed out after 1 seconds while running test scanner")
  #expect(store.lastRefreshError == store.errorMessage)
  #expect(store.lastRefreshDuration != nil)
}

@MainActor
@Test func statusMenuRefreshesEveryTimeMenuOpens() async {
  let client = CountingPortManagerClient(result: [])
  let store = PortStore(cliClient: client)
  let controller = PortManagerStatusMenuController(portStore: store, mainWindowController: nil)

  controller.menuWillOpen(NSMenu())
  await client.waitForListCalls(1)
  await waitForIdle(store)
  controller.menuWillOpen(NSMenu())
  await client.waitForListCalls(2)
  await waitForIdle(store)

  #expect(await client.listCallCount == 2)
}

@MainActor
private func waitForIdle(_ store: PortStore) async {
  while store.isLoading {
    try? await Task.sleep(for: .milliseconds(5))
  }
}

@MainActor
@Test func mainWindowAndStatusMenuUseSameStoreInstance() {
  let store = PortStore(cliClient: CountingPortManagerClient(result: []))
  let windowController = PortManagerMainWindowController(portStore: store)
  let statusController = PortManagerStatusMenuController(portStore: store, mainWindowController: windowController)

  #expect(windowController.portStore === store)
  #expect(statusController.portStore === store)
}

actor CountingPortManagerClient: PortManagerCLIClientProtocol {
  nonisolated let activeScannerCommand = "test scanner"

  private let result: [ListeningPort]
  private let listError: Error?
  private let killError: Error?
  private(set) var listCallCount = 0
  private(set) var killCallCount = 0

  init(result: [ListeningPort], listError: Error? = nil, killError: Error? = nil) {
    self.result = result
    self.listError = listError
    self.killError = killError
  }

  func listPorts() async throws -> [ListeningPort] {
    listCallCount += 1
    try await Task.sleep(for: .milliseconds(25))
    if let listError {
      throw listError
    }
    return result
  }

  func killPort(_ port: ListeningPort) async throws -> KillPortResult {
    killCallCount += 1
    if let killError {
      throw killError
    }
    return KillPortResult(ok: true, killed: [], failed: [])
  }

  func waitForListCalls(_ expectedCount: Int) async {
    while listCallCount < expectedCount {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}
