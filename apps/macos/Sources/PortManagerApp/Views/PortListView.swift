import SwiftUI

struct PortListView: View {
  @Bindable var store: PortStore

  var body: some View {
    List(selection: $store.selection) {
      Section {
        ForEach(store.filteredPorts) { port in
          PortRowView(port: port)
            .tag(port.id)
        }
      } header: {
        ListHeaderView(store: store)
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
