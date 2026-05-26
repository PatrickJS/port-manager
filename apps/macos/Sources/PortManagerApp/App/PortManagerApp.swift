import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if Self.shouldShowDockIcon {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    } else {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  private static var shouldShowDockIcon: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    let environment = ProcessInfo.processInfo.environment
    return arguments.contains("--dock") || environment["PORT_MANAGER_DOCK"] == "1"
  }
}

@main
struct PortManagerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    Window("Port Manager", id: "main") {
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
        Button("Kill Selected Port") {
          NotificationCenter.default.post(name: .killSelectedPortRequested, object: nil)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
      }
    }
    MenuBarExtra("Port Manager", systemImage: "network") {
      Button("Open Port Manager") {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      }
      Divider()
      Button("Refresh Ports") {
        NotificationCenter.default.post(name: .refreshPortsRequested, object: nil)
      }
      Button("Kill Selected Port") {
        NotificationCenter.default.post(name: .killSelectedPortRequested, object: nil)
      }
      Divider()
      Button("Quit Port Manager") {
        NSApp.terminate(nil)
      }
    }
  }
}

extension Notification.Name {
  static let refreshPortsRequested = Notification.Name("PortManagerRefreshPortsRequested")
  static let killSelectedPortRequested = Notification.Name("PortManagerKillSelectedPortRequested")
}
