import SwiftUI

struct PortListView: View {
  @Bindable var store: PortStore
  @State private var collapsedGroupIDs: Set<String> = ["os-apple", "system"]

  var body: some View {
    List(selection: $store.selection) {
      Section {
        ListHeaderView(store: store)
      }

      ForEach(portSections) { section in
        Section {
          if !isCollapsed(section) {
            ForEach(section.ports) { port in
              PortRowView(port: port)
                .tag(port.id)
            }
          }
        } header: {
          PortSectionHeaderView(
            section: section,
            isCollapsed: isCollapsed(section),
            toggle: { toggle(section) }
          )
        }
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if let errorMessage = store.errorMessage {
        ContentUnavailableView("Port Manager CLI Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
      } else if store.isLoading && store.ports.isEmpty {
        ProgressView("Scanning Ports")
      } else if store.filteredPorts.isEmpty {
        ContentUnavailableView("No Ports", systemImage: "network", description: Text("No matching listening TCP ports were found."))
      }
    }
  }

  private var portSections: [PortListSection] {
    let grouped = Dictionary(grouping: store.filteredPorts, by: \.displayGroup)
    return grouped
      .map { group, ports in
        PortListSection(group: group, ports: ports.sorted(by: sortPorts))
      }
      .sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
          return lhs.rank < rhs.rank
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  private var hasActiveSearch: Bool {
    !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func isCollapsed(_ section: PortListSection) -> Bool {
    !hasActiveSearch && collapsedGroupIDs.contains(section.id)
  }

  private func toggle(_ section: PortListSection) {
    if collapsedGroupIDs.contains(section.id) {
      collapsedGroupIDs.remove(section.id)
    } else {
      collapsedGroupIDs.insert(section.id)
    }
  }

  private func sortPorts(_ lhs: ListeningPort, _ rhs: ListeningPort) -> Bool {
    if lhs.primaryPort != rhs.primaryPort {
      return (lhs.primaryPort ?? 0) < (rhs.primaryPort ?? 0)
    }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}

private struct ListHeaderView: View {
  let store: PortStore

  var body: some View {
    HStack {
      Text("\(store.filteredPorts.count) Ports")
      Spacer()
      if store.isLoading {
        ProgressView()
          .controlSize(.small)
      }
    }
  }
}

private struct PortSectionHeaderView: View {
  let section: PortListSection
  let isCollapsed: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 6) {
        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(width: 10)

        Text(section.name)

        Text("\(section.ports.count)")
          .font(.caption2)
          .foregroundStyle(.secondary)

        if section.isSafeToIgnore {
          Text("Safe to ignore")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct PortRowView: View {
  let port: ListeningPort

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: iconName)
        .foregroundStyle(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(port.title)
            .lineLimit(1)

          Text(verbatim: "PID \(port.pid)")
            .font(.caption)
            .foregroundStyle(.secondary)

          if port.status == .reserved {
            Text(port.status.label)
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }

        Text(port.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private var iconName: String {
    if port.status == .reserved {
      return "lock"
    }
    if port.binds.contains(where: { $0.commonPort != nil }) {
      return "tag"
    }
    return "network"
  }
}

private struct PortListSection: Identifiable {
  let id: String
  let name: String
  let rank: Int
  let ports: [ListeningPort]

  var isSafeToIgnore: Bool {
    id == "os-apple" || id == "system"
  }

  init(group: PortDisplayGroup, ports: [ListeningPort]) {
    id = group.id
    name = group.name
    rank = group.rank
    self.ports = ports
  }
}
