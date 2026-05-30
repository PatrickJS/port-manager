import SwiftUI

struct ContentView: View {
  let store: PortStore
  @State private var inspectionStore = PortInspectionStore()
  @State private var groupingRulesStore = PortGroupingRulesStore()
  @State private var pendingKill: ListeningPort?
  @State private var showingSettings = false

  var body: some View {
    @Bindable var store = store

    NavigationSplitView {
      PortListView(
        store: store,
        groupingRules: groupingRulesStore.rules,
        groups: groupingRulesStore.groups
      )
        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
    } detail: {
      if showingSettings {
        SettingsView(portStore: store)
      } else {
        PortDetailView(
          port: store.selectedPort,
          allPorts: store.ports,
          groupingRules: groupingRulesStore.rules,
          inspectionStore: inspectionStore
        ) { port in
          pendingKill = port
        }
      }
    }
    .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search ports, apps, users")
    .toolbar {
      ToolbarItem {
        Button {
          showingSettings.toggle()
        } label: {
          Label(showingSettings ? "Show Port Details" : "Settings", systemImage: showingSettings ? "sidebar.right" : "gearshape")
        }
        .help(showingSettings ? "Return to port details" : "Show Port Manager settings")
      }
      ToolbarItem {
        Button {
          Task { await store.refresh() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(store.isLoading)
      }
      ToolbarItem {
        Button {
          if let port = store.selectedPort, port.canKill {
            pendingKill = port
          }
        } label: {
          Label("Kill Port", systemImage: "xmark.octagon")
        }
        .disabled(showingSettings || store.selectedPort?.canKill != true || store.isKilling)
      }
    }
    .alert("Kill Port?", isPresented: killAlertBinding, presenting: pendingKill) { port in
      Button("Cancel", role: .cancel) {
        pendingKill = nil
      }
      Button("Kill Port", role: .destructive) {
        pendingKill = nil
        Task { await store.kill(port) }
      }
    } message: { port in
      Text("Send SIGTERM to \(port.killDescription).")
    }
    .task {
      await store.refresh(force: true)
    }
    .onReceive(NotificationCenter.default.publisher(for: .refreshPortsRequested)) { _ in
      Task { await store.refresh(force: true) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .killSelectedPortRequested)) { _ in
      if let port = store.selectedPort, port.canKill {
        pendingKill = port
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .groupingRulesChanged)) { _ in
      groupingRulesStore.reload()
    }
    .onReceive(NotificationCenter.default.publisher(for: .showSettingsRequested)) { _ in
      showingSettings = true
    }
  }

  private var killAlertBinding: Binding<Bool> {
    Binding {
      pendingKill != nil
    } set: { isPresented in
      if !isPresented {
        pendingKill = nil
      }
    }
  }
}
