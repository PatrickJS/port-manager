import SwiftUI

struct ContentView: View {
  @State private var store = PortStore()

  var body: some View {
    @Bindable var store = store

    NavigationSplitView {
      PortListView(store: store)
        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
    } detail: {
      PortDetailView(port: store.selectedPort)
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
    }
    .task {
      await store.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .refreshPortsRequested)) { _ in
      Task { await store.refresh() }
    }
  }
}
