import SwiftUI

struct SettingsView: View {
  @State private var store = LaunchAgentSettingsStore()

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Start at login and keep running", isOn: enabledBinding)

        Picker("Launch target", selection: targetBinding) {
          ForEach(LaunchAgentTarget.allCases) { target in
            Text(target.title)
              .tag(target)
          }
        }
        .pickerStyle(.segmented)

        Text(store.selectedTarget.detail)
          .foregroundStyle(.secondary)

        LabeledContent("App bundle") {
          Text(store.resolvedTargetPath)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
      }

      Section("Diagnostics") {
        Button("Refresh Diagnostics") {
          store.refreshDiagnostics()
        }

        LabeledContent("Launcher") {
          Text(store.launcherPath)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }

        diagnosticsBlock(title: "launchctl", text: store.launchctlStatus)
        diagnosticsBlock(title: "stdout log", text: store.stdoutLog)
        diagnosticsBlock(title: "stderr log", text: store.stderrLog)
      }

      if let statusMessage = store.statusMessage {
        Text(statusMessage)
          .foregroundStyle(.secondary)
      }

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
      }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 560)
    .task {
      store.reload()
    }
  }

  private var enabledBinding: Binding<Bool> {
    Binding {
      store.isEnabled
    } set: { enabled in
      Task {
        await store.setEnabled(enabled)
      }
    }
  }

  private var targetBinding: Binding<LaunchAgentTarget> {
    Binding {
      store.selectedTarget
    } set: { target in
      Task {
        await store.setTarget(target)
      }
    }
  }

  private func diagnosticsBlock(title: String, text: String) -> some View {
    LabeledContent(title) {
      ScrollView {
        Text(text)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: 34, maxHeight: 120)
    }
  }
}
