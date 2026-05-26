import SwiftUI

struct PortDetailView: View {
  let port: ListeningPort?

  var body: some View {
    Group {
      if let port {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HeaderSection(port: port)
            DetailSection(title: "Bindings") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(port.binds) { bind in
                  BindRow(bind: bind)
                }
              }
            }
            DetailSection(title: "Ownership") {
              MetadataGrid(rows: ownershipRows(for: port))
            }
            DetailSection(title: "Evidence") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(port.ownershipEvidence, id: \.self) { evidence in
                  EvidenceLine(text: evidence)
                }
              }
            }
          }
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        ContentUnavailableView("Select a Port", systemImage: "network", description: Text("Choose a listening port from the sidebar."))
      }
    }
  }

  private func ownershipRows(for port: ListeningPort) -> [MetadataRow] {
    [
      MetadataRow(label: "Process", value: port.title),
      MetadataRow(label: "Status", value: port.status.label),
      MetadataRow(label: "PID", value: "\(port.pid)"),
      MetadataRow(label: "User", value: port.uid.map { "\(port.user) (\($0))" } ?? port.user),
      MetadataRow(label: "Parent PID", value: port.parentPid.map(String.init) ?? "Unknown"),
      MetadataRow(label: "Confidence", value: port.confidence.rawValue),
      MetadataRow(label: "Command", value: port.command ?? "Unknown"),
      MetadataRow(label: "Arguments", value: port.arguments ?? "Unknown"),
      MetadataRow(label: "Working Directory", value: port.currentDirectory ?? "Unknown"),
      MetadataRow(label: "Launch Originator", value: port.launchOriginator ?? "Unknown")
    ]
  }
}

private struct HeaderSection: View {
  let port: ListeningPort

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(port.title)
        .font(.largeTitle)
        .fontWeight(.semibold)
        .lineLimit(2)

      Text(port.ownershipSummary)
        .font(.title3)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      HStack(spacing: 8) {
        Label(port.status.label, systemImage: port.status == .reserved ? "lock" : "network")
        Label(port.confidence.rawValue, systemImage: "checkmark.seal")
        Text(verbatim: "PID \(port.pid)")
        Text(port.user)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct BindRow: View {
  let bind: PortBind

  var body: some View {
    HStack(spacing: 10) {
      Text(verbatim: "\(bind.host):\(bind.port)")
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)

      Text(bind.proto)
        .font(.caption)
        .foregroundStyle(.secondary)

      if let commonPort = bind.commonPort {
        Text(commonPort.name)
          .font(.caption)
          .foregroundStyle(.green)
      }

      Spacer()
    }
  }
}

private struct DetailSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      content
    }
  }
}

private struct MetadataGrid: View {
  let rows: [MetadataRow]

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
      ForEach(rows) { row in
        GridRow {
          Text(row.label)
            .foregroundStyle(.secondary)
          Text(row.value)
            .textSelection(.enabled)
        }
      }
    }
  }
}

private struct MetadataRow: Identifiable {
  let id = UUID()
  let label: String
  let value: String
}

private struct EvidenceLine: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "circle.fill")
        .font(.system(size: 5))
        .padding(.top, 7)
        .foregroundStyle(.secondary)
      Text(text)
        .textSelection(.enabled)
    }
  }
}
