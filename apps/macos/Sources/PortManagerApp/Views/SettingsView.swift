import SwiftUI

struct SettingsView: View {
  @State private var store = LaunchAgentSettingsStore()
  @State private var groupingStore = PortGroupingRulesStore()

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

      Section("Grouping Rules") {
        Text("Matched top to bottom. Rules can rename app clusters and move matching ports into a section.")
          .foregroundStyle(.secondary)

        ForEach(groupingStore.rules.indices, id: \.self) { index in
          GroupingRuleEditor(
            rule: ruleBinding(at: index),
            canMoveUp: index > 0,
            canMoveDown: index < groupingStore.rules.count - 1,
            moveUp: { moveRule(from: index, offset: -1) },
            moveDown: { moveRule(from: index, offset: 1) },
            delete: { groupingStore.rules.remove(at: index) }
          )
        }

        HStack {
          Button {
            groupingStore.addRule()
          } label: {
            Label("Add Rule", systemImage: "plus")
          }

          Button {
            groupingStore.resetDefaults()
          } label: {
            Label("Reset Defaults", systemImage: "arrow.counterclockwise")
          }
        }
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

  private func ruleBinding(at index: Int) -> Binding<PortGroupingRule> {
    Binding {
      groupingStore.rules[index]
    } set: { newValue in
      groupingStore.rules[index] = newValue
    }
  }

  private func moveRule(from index: Int, offset: Int) {
    let destination = index + offset
    guard groupingStore.rules.indices.contains(index),
          groupingStore.rules.indices.contains(destination)
    else {
      return
    }
    groupingStore.rules.swapAt(index, destination)
  }
}

private struct GroupingRuleEditor: View {
  @Binding var rule: PortGroupingRule
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void
  let delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Toggle("Enabled", isOn: $rule.isEnabled)

        Spacer()

        Button(action: moveUp) {
          Label("Move Up", systemImage: "chevron.up")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMoveUp)

        Button(action: moveDown) {
          Label("Move Down", systemImage: "chevron.down")
        }
        .labelStyle(.iconOnly)
        .disabled(!canMoveDown)

        Button(role: .destructive, action: delete) {
          Label("Delete", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
      }

      HStack {
        TextField("Match text", text: $rule.match)
          .textFieldStyle(.roundedBorder)

        Picker("Mode", selection: $rule.matchMode) {
          ForEach(PortGroupingMatchMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .frame(width: 130)
      }

      HStack {
        TextField("Group as", text: $rule.title)
          .textFieldStyle(.roundedBorder)

        Picker("Section", selection: $rule.displayGroupID) {
          ForEach(PortGroupingCategories.defaults) { group in
            Text(group.name).tag(group.id)
          }
        }
        .frame(width: 160)
      }
    }
    .padding(.vertical, 6)
  }
}
