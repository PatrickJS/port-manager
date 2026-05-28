import AppKit
import SwiftUI

@MainActor
enum PortManagerAppLifecycle {
  static var userRequestedTermination = false

  static func quit() {
    userRequestedTermination = true
    NSApp.terminate(nil)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    ProcessInfo.processInfo.disableAutomaticTermination("Port Manager menu bar agent")
    if Self.shouldShowDockIcon {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    } else {
      NSApp.setActivationPolicy(.accessory)
      DispatchQueue.main.async {
        NSApp.windows
          .filter { $0.identifier?.rawValue == "main" || $0.title == "Port Manager" }
          .forEach { $0.close() }
      }
    }
  }

  private static var shouldShowDockIcon: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    let environment = ProcessInfo.processInfo.environment
    return arguments.contains("--dock") || environment["PORT_MANAGER_DOCK"] == "1"
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if PortManagerAppLifecycle.userRequestedTermination || Self.shouldShowDockIcon {
      return .terminateNow
    }
    return .terminateCancel
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
    .defaultLaunchBehavior(.suppressed)
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
    MenuBarExtra {
      MenuBarPortsView {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      }
    } label: {
      Image(systemName: "chart.bar.xaxis")
    }
    Settings {
      SettingsView()
    }
  }
}

extension Notification.Name {
  static let refreshPortsRequested = Notification.Name("PortManagerRefreshPortsRequested")
  static let killSelectedPortRequested = Notification.Name("PortManagerKillSelectedPortRequested")
}
