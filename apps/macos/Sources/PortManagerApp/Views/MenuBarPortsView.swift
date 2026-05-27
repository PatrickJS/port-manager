import AppKit
import SwiftUI

struct MenuBarPortsView: View {
  @State private var store = PortStore()
  let openMainWindow: () -> Void

  var body: some View {
    Group {
      portRows
      Divider()
      Button("Open Port Manager") {
        openMainWindow()
      }
      SettingsLink {
        Text("Settings")
      }
      Button("Refresh Ports") {
        Task { await store.refresh() }
      }
      Divider()
      Button("Quit Port Manager") {
        NSApp.terminate(nil)
      }
    }
    .task {
      await store.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .refreshPortsRequested)) { _ in
      Task { await store.refresh() }
    }
  }

  @ViewBuilder
  private var portRows: some View {
    if store.isLoading && store.ports.isEmpty {
      Text("Scanning Ports")
    } else if let errorMessage = store.errorMessage {
      Text(truncated(errorMessage))
    } else if store.ports.isEmpty {
      Text("No Open Ports")
    } else {
      ForEach(Array(regularMenuSections.enumerated()), id: \.element.id) { index, section in
        if index > 0 {
          Divider()
        }
        Section(section.name) {
          ForEach(section.clusters) { cluster in
            clusterMenu(cluster)
          }
        }
      }
      if !safeMenuSections.isEmpty {
        Divider()
        ForEach(safeMenuSections) { section in
          Menu("\(section.name) · Safe to ignore (\(section.ports.count))") {
            ForEach(section.clusters) { cluster in
              clusterMenu(cluster)
            }
          }
        }
      }
    }
  }

  private var regularMenuSections: [MenuPortSection] {
    menuSections.filter { !$0.isSafeToIgnore }
  }

  private var safeMenuSections: [MenuPortSection] {
    menuSections.filter(\.isSafeToIgnore)
  }

  private var menuSections: [MenuPortSection] {
    let visiblePorts = Array(store.ports.prefix(40))
    let groups = Dictionary(grouping: visiblePorts, by: \.displayGroup)
    return groups
      .map { group, ports in
        MenuPortSection(group: group, ports: ports.sorted(by: sortPorts))
      }
      .sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
          return lhs.rank < rhs.rank
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  private func sortPorts(_ lhs: ListeningPort, _ rhs: ListeningPort) -> Bool {
    (lhs.primaryPort ?? 0) < (rhs.primaryPort ?? 0)
  }

  private func portMenu(_ port: ListeningPort) -> some View {
    Menu(menuTitle(for: port)) {
      Text(port.title)
      if let groupReason = port.groupReason {
        Text(groupReason)
      }
      ForEach(port.binds) { bind in
        Text(verbatim: bindingTitle(for: bind))
      }
      Text(verbatim: port.ownerCount == 1 ? "PID \(port.pid)" : "\(port.ownerCount) owners")
      if let commonPort = port.binds.first?.commonPort {
        Text(commonPort.name)
      }
      Divider()
      Button(port.binds.count == 1 ? "Copy Binding" : "Copy Bindings") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(port.bindingLabels, forType: .string)
      }
      Button("Open Port Manager") {
        openMainWindow()
      }
      if port.canKill {
        Button("Kill Port", role: .destructive) {
          Task { await kill(port) }
        }
      }
    }
  }

  @ViewBuilder
  private func clusterMenu(_ cluster: PortCluster) -> some View {
    if cluster.isSinglePort, let port = cluster.firstPort {
      portMenu(port)
    } else {
      Menu(clusterTitle(for: cluster)) {
        Text("\(cluster.portCount) ports")
        if !cluster.portList.isEmpty {
          Text("Ports \(cluster.portList)")
        }
        Divider()
        ForEach(cluster.ports) { port in
          portMenu(port)
        }
      }
    }
  }

  private func clusterTitle(for cluster: PortCluster) -> String {
    truncated("\(cluster.title) · \(cluster.portCount) ports")
  }

  private func menuTitle(for port: ListeningPort) -> String {
    let title = "\(port.primaryPort.map(String.init) ?? "?") · \(port.title)"
    return truncated(title)
  }

  private func bindingTitle(for bind: PortBind) -> String {
    if let ownerLabel = bind.ownerLabel {
      return truncated("\(bind.host):\(bind.port) · \(ownerLabel)")
    }
    return truncated("\(bind.host):\(bind.port)")
  }

  @MainActor
  private func kill(_ port: ListeningPort) async {
    guard confirmKill(port) else { return }
    await store.kill(port)
  }

  @MainActor
  private func confirmKill(_ port: ListeningPort) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Kill Port?"
    alert.informativeText = "Send SIGTERM to \(port.killDescription)."
    alert.addButton(withTitle: "Kill Port")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func truncated(_ value: String) -> String {
    if value.count <= 30 {
      return value
    }
    return "\(value.prefix(29))..."
  }
}

private struct MenuPortSection: Identifiable {
  let id: String
  let name: String
  let rank: Int
  let ports: [ListeningPort]
  let clusters: [PortCluster]

  var isSafeToIgnore: Bool {
    id == "os-apple" || id == "system"
  }

  init(group: PortDisplayGroup, ports: [ListeningPort]) {
    id = group.id
    name = group.name
    rank = group.rank
    self.ports = ports
    clusters = portClusters(for: ports, namespace: group.id)
  }
}
