import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct PortManagerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("Port Manager", id: "main") {
      ContentView()
        .frame(minWidth: 980, minHeight: 620)
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandMenu("Ports") {
        Button("Refresh") {
          NotificationCenter.default.post(name: .refreshPortsRequested, object: nil)
        }
        .keyboardShortcut("r", modifiers: .command)
      }
    }
  }
}

extension Notification.Name {
  static let refreshPortsRequested = Notification.Name("PortManagerRefreshPortsRequested")
}
