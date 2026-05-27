import SwiftUI

struct ContentView: View {
  @State private var store = PortStore()
  @State private var inspectionStore = PortInspectionStore()
  @State private var pendingKill: ListeningPort?

  var body: some View {
    @Bindable var store = store

    NavigationSplitView {
      PortListView(store: store)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
    } detail: {
      PortDetailView(
        port: store.selectedPort,
        allPorts: store.ports,
        inspectionStore: inspectionStore
      ) { port in
        pendingKill = port
      }
    }
    .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search ports, apps, users")
    .toolbar {
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
        .disabled(store.selectedPort?.canKill != true || store.isKilling)
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
      await store.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .refreshPortsRequested)) { _ in
      Task { await store.refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .killSelectedPortRequested)) { _ in
      if let port = store.selectedPort, port.canKill {
        pendingKill = port
      }
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
