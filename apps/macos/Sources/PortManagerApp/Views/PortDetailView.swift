import SwiftUI

struct PortDetailView: View {
  let port: ListeningPort?
  let allPorts: [ListeningPort]
  let groupingRules: [PortGroupingRule]
  let inspectionStore: PortInspectionStore
  let onKill: (ListeningPort) -> Void

  var body: some View {
    Group {
      if let port {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HeaderSection(port: port, onKill: onKill)
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
            InspectionSection(
              port: port,
              allPorts: allPorts,
              groupingRules: groupingRules,
              inspectionStore: inspectionStore
            )
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
      MetadataRow(label: "Owners", value: "\(port.ownerCount)"),
      MetadataRow(label: "Bindings", value: "\(port.entryCount)"),
      MetadataRow(label: "PID", value: port.ownerCount == 1 ? "\(port.pid)" : "Multiple"),
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

private struct InspectionSection: View {
  let port: ListeningPort
  let allPorts: [ListeningPort]
  let groupingRules: [PortGroupingRule]
  let inspectionStore: PortInspectionStore

  var body: some View {
    let clusterKey = portClusterKey(for: port, rules: groupingRules)
    let clusterTitle = portClusterTitle(for: port, rules: groupingRules)
    let relatedPorts = allPorts.filter { portClusterKey(for: $0, rules: groupingRules) == clusterKey }
    let currentWarnings = PortExpectationChecker.warnings(for: relatedPorts, title: clusterTitle)
    let inspection = inspectionStore.inspections[clusterKey]
    DetailSection(title: "AI Inspection") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Button {
            Task {
              await inspectionStore.inspect(port: port, allPorts: allPorts, rules: groupingRules)
            }
          } label: {
            Label(inspection == nil ? "Ask AI" : "Inspect Again", systemImage: "sparkles")
          }
          .disabled(inspectionStore.isInspecting(port, rules: groupingRules))

          if inspectionStore.isInspecting(port, rules: groupingRules) {
            ProgressView()
              .controlSize(.small)
          }

          if let inspection {
            Text("Saved \(inspection.generatedAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if inspection == nil, !currentWarnings.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(currentWarnings) { warning in
              Label(warning.message, systemImage: warning.severity == "notice" ? "info.circle" : "exclamationmark.triangle")
                .foregroundStyle(warning.severity == "notice" ? Color.secondary : Color.orange)
                .textSelection(.enabled)
            }
            Text("Ask AI to inspect this warning with current process evidence and online app details.")
              .foregroundStyle(.secondary)
          }
        }

        if let inspection {
          if let warnings = inspection.warnings, !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(warnings) { warning in
                Label(warning.message, systemImage: warning.severity == "notice" ? "info.circle" : "exclamationmark.triangle")
                  .foregroundStyle(warning.severity == "notice" ? Color.secondary : Color.orange)
                  .textSelection(.enabled)
              }
            }
          }

          Text(inspection.summary)
            .textSelection(.enabled)

          VStack(alignment: .leading, spacing: 8) {
            ForEach(inspection.details, id: \.self) { detail in
              EvidenceLine(text: detail)
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Basis")
              .font(.caption)
              .foregroundStyle(.secondary)
            ForEach(inspection.basis, id: \.self) { basis in
              Text(basis)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }

          if let sources = inspection.sources, !sources.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Online Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(sources) { source in
                if let url = URL(string: source.url) {
                  Link(source.title, destination: url)
                } else {
                  Text(source.title)
                }
                if let snippet = source.snippet, !snippet.isEmpty {
                  Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
              }
            }
          }
        } else {
          Text("Inspect this app cluster to generate and save an explanation from current process evidence and online app details.")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct HeaderSection: View {
  let port: ListeningPort
  let onKill: (ListeningPort) -> Void

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
        Text(verbatim: port.ownerCount == 1 ? "PID \(port.pid)" : "\(port.ownerCount) owners")
        Text(port.user)
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Button(role: .destructive) {
        onKill(port)
      } label: {
        Label("Kill Port", systemImage: "xmark.octagon")
      }
      .disabled(!port.canKill)
      .help(port.canKill ? "Send SIGTERM to this process" : "Only listening process owners can be killed")
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

      if let ownerLabel = bind.ownerLabel {
        Text(ownerLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

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
