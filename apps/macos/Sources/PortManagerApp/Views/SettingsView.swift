import SwiftUI

struct SettingsView: View {
  let portStore: PortStore?
  @State private var store = LaunchAgentSettingsStore()
  @State private var groupingStore = PortGroupingRulesStore()
  @State private var aiStore = LocalAISettingsStore()
  @State private var showDeveloperSettings = false

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Start at login and keep running", isOn: enabledBinding)
      }

      Section {
        DisclosureGroup("Developer Settings", isExpanded: $showDeveloperSettings) {
          Toggle("Use local dist build", isOn: localDistBinding)

          Text(store.selectedTarget.detail)
            .foregroundStyle(.secondary)

          LabeledContent("App bundle") {
            Text(store.resolvedTargetPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

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
          if let portStore {
            LabeledContent("Scanner") {
              Text(portStore.activeScannerCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
            LabeledContent("Last refresh") {
              Text(refreshSummary(for: portStore))
                .font(.caption)
                .textSelection(.enabled)
            }
            if let lastRefreshError = portStore.lastRefreshError {
              diagnosticsBlock(title: "scanner error", text: lastRefreshError)
            }
          }
        }
      }

      Section("AI Inspection") {
        Picker("Provider", selection: aiProviderBinding) {
          ForEach(LocalAIProviderMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        Toggle("Prefer Codex in Auto", isOn: preferCodexBinding)
        Toggle("Online research", isOn: onlineResearchBinding)

        LabeledContent("Ollama URL") {
          TextField("Ollama URL", text: ollamaBaseURLBinding)
            .textFieldStyle(.roundedBorder)
        }

        if selectableOllamaModels.isEmpty {
          LabeledContent("Ollama model") {
            TextField("Auto recommended", text: ollamaModelBinding)
              .textFieldStyle(.roundedBorder)
          }
        } else {
          Picker("Ollama model", selection: ollamaModelBinding) {
            if let recommended = aiStore.recommendedOllamaModel {
              Text("Recommended: \(recommended)").tag(recommended)
            }
            ForEach(selectableOllamaModels.filter { $0 != aiStore.recommendedOllamaModel }, id: \.self) { model in
              Text(model).tag(model)
            }
          }
        }

        LabeledContent("Codex command") {
          TextField("codex", text: codexCommandBinding)
            .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Prompt")
            Spacer()
            Button("Reset Prompt") {
              aiStore.resetPromptTemplate()
            }
          }
          TextEditor(text: promptTemplateBinding)
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 150)
        }

        HStack {
          Button("Check AI Providers") {
            Task { await aiStore.checkProviders() }
          }
          .disabled(aiStore.isChecking)

          if aiStore.isChecking {
            ProgressView()
              .controlSize(.small)
          }
        }

        Text(aiStore.statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Section("Groups") {
        Text("Create, edit, delete, and reset the sections shown in the app, menu-bar dropdown, Raycast, and AI explanations. Use plain names and stable IDs so a junior engineer or AI agent can refer to them clearly.")
          .foregroundStyle(.secondary)

        ForEach(groupingStore.groups.indices, id: \.self) { index in
          GroupEditor(
            group: groupBinding(at: index),
            canDelete: groupingStore.groups.count > 1,
            delete: { groupingStore.deleteGroup(at: index) }
          )
        }

        HStack {
          Button {
            groupingStore.addGroup()
          } label: {
            Label("Add Group", systemImage: "plus")
          }

          Button {
            groupingStore.resetGroups()
          } label: {
            Label("Reset Default Groups", systemImage: "arrow.counterclockwise")
          }
        }
      }

      Section("Grouping Rules") {
        Text("Create, edit, delete, reorder, and reset matching rules. Rules run top to bottom. A rule says: when process, command, arguments, working directory, owner, or known port text matches, rename that app cluster and place it in a group.")
          .foregroundStyle(.secondary)

        ForEach(groupingStore.rules.indices, id: \.self) { index in
          GroupingRuleEditor(
            rule: ruleBinding(at: index),
            groups: groupingStore.groups,
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
            groupingStore.resetRules()
          } label: {
            Label("Reset Default Rules", systemImage: "arrow.counterclockwise")
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
    .frame(maxWidth: 760, alignment: .leading)
    .task {
      store.reload()
      aiStore.reload()
      await aiStore.checkProviders()
    }
  }

  init(portStore: PortStore? = nil) {
    self.portStore = portStore
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

  private var localDistBinding: Binding<Bool> {
    Binding {
      store.selectedTarget == .localDist
    } set: { useLocalDist in
      Task {
        await store.setTarget(useLocalDist ? .localDist : .currentApp)
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

  private func refreshSummary(for portStore: PortStore) -> String {
    guard let lastRefreshStarted = portStore.lastRefreshStarted else {
      return "Not run yet"
    }

    let started = lastRefreshStarted.formatted(date: .abbreviated, time: .standard)
    let updated = portStore.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "no successful scan"
    let duration = portStore.lastRefreshDuration.map { String(format: "%.2fs", $0) } ?? "running"
    return "Started \(started), updated \(updated), duration \(duration)"
  }

  private var aiProviderBinding: Binding<LocalAIProviderMode> {
    Binding {
      aiStore.settings.providerMode
    } set: { value in
      aiStore.settings.providerMode = value
    }
  }

  private var preferCodexBinding: Binding<Bool> {
    Binding {
      aiStore.settings.preferCodexInAuto
    } set: { value in
      aiStore.settings.preferCodexInAuto = value
    }
  }

  private var onlineResearchBinding: Binding<Bool> {
    Binding {
      aiStore.settings.onlineResearchEnabled
    } set: { value in
      aiStore.settings.onlineResearchEnabled = value
    }
  }

  private var ollamaBaseURLBinding: Binding<String> {
    Binding {
      aiStore.settings.ollamaBaseURL
    } set: { value in
      aiStore.settings.ollamaBaseURL = value
    }
  }

  private var ollamaModelBinding: Binding<String> {
    Binding {
      aiStore.settings.ollamaModel
    } set: { value in
      aiStore.settings.ollamaModel = value
    }
  }

  private var selectableOllamaModels: [String] {
    aiStore.availableOllamaModels.filter(LocalAIInspectionService.isGenerativeOllamaModel)
  }

  private var codexCommandBinding: Binding<String> {
    Binding {
      aiStore.settings.codexCommand
    } set: { value in
      aiStore.settings.codexCommand = value
    }
  }

  private var promptTemplateBinding: Binding<String> {
    Binding {
      aiStore.settings.promptTemplate
    } set: { value in
      aiStore.settings.promptTemplate = value
    }
  }

  private func groupBinding(at index: Int) -> Binding<PortDisplayGroup> {
    Binding {
      groupingStore.groups[index]
    } set: { newValue in
      groupingStore.groups[index] = newValue
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

private struct GroupEditor: View {
  @Binding var group: PortDisplayGroup
  let canDelete: Bool
  let delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Group name", text: $group.name)
          .textFieldStyle(.roundedBorder)

        Stepper("Rank \(group.rank)", value: $group.rank, in: 0...999, step: 10)
          .frame(width: 120)

        Button(role: .destructive, action: delete) {
          Label("Delete Group", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .disabled(!canDelete || group.id == PortDisplayGroup.other.id)
      }

      Text("ID: \(group.id)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Text("CRUD: add with Add Group, edit name/rank here, delete with trash, restore defaults with Reset Default Groups.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }
}

private struct GroupingRuleEditor: View {
  @Binding var rule: PortGroupingRule
  let groups: [PortDisplayGroup]
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void
  let delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(ruleSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      Text("Rule ID: \(rule.id)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

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
        LabeledContent("When text") {
          TextField("cursor helper, ollama, goalbuddy", text: $rule.match)
            .textFieldStyle(.roundedBorder)
        }

        Picker("Mode", selection: $rule.matchMode) {
          ForEach(PortGroupingMatchMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .frame(width: 130)
      }

      HStack {
        LabeledContent("Name cluster") {
          TextField("Cursor, Ollama, GoalBuddy", text: $rule.title)
            .textFieldStyle(.roundedBorder)
        }

        Picker("Section", selection: $rule.displayGroupID) {
          ForEach(groups) { group in
            Text(group.name).tag(group.id)
          }
        }
        .frame(width: 160)
      }
    }
    .padding(.vertical, 6)
  }

  private var ruleSummary: String {
    let matchText = rule.match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "<match text>"
      : rule.match
    let title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "<cluster name>"
      : rule.title
    let groupName = groups.first { $0.id == rule.displayGroupID }?.name ?? rule.displayGroupID
    return "If evidence \(rule.matchMode.title.lowercased())-matches \"\(matchText)\", show it as \"\(title)\" in \"\(groupName)\"."
  }
}
