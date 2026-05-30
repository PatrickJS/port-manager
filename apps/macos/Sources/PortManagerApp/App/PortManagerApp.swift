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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstance = PortManagerSingleInstance()
  private let portStore = PortStore()
  private lazy var mainWindowController = PortManagerMainWindowController(portStore: portStore)
  private lazy var statusMenuController = PortManagerStatusMenuController(
    portStore: portStore,
    mainWindowController: mainWindowController
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard singleInstance.acquire() else {
      if Self.shouldShowDockIcon {
        PortManagerSingleInstance.requestMainWindowFromRunningInstance()
      }
      NSApp.terminate(nil)
      return
    }

    ProcessInfo.processInfo.disableAutomaticTermination("Port Manager menu bar agent")
    PortManagerSingleInstance.addMainWindowObserver(self, selector: #selector(showMainWindowRequestedFromAnotherInstance))
    configureMainMenu()
    statusMenuController.start()

    if Self.shouldShowDockIcon {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      DispatchQueue.main.async {
        self.mainWindowController.show()
      }
    } else {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
  }

  static var shouldShowDockIcon: Bool {
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

  @MainActor
  @objc private func showMainWindowRequestedFromAnotherInstance(_ notification: Notification) {
    mainWindowController.show()
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu(title: "Port Manager")
    appMenu.addItem(
      NSMenuItem(
        title: "Quit Port Manager",
        action: #selector(quitFromMenu),
        keyEquivalent: "q"
      )
    )
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let portsMenuItem = NSMenuItem()
    let portsMenu = NSMenu(title: "Ports")
    portsMenu.addItem(
      NSMenuItem(
        title: "Refresh",
        action: #selector(refreshFromMenu),
        keyEquivalent: "r"
      )
    )
    portsMenu.addItem(
      NSMenuItem(
        title: "Kill Selected Port",
        action: #selector(killSelectedPortFromMenu),
        keyEquivalent: "K"
      )
    )
    portsMenuItem.submenu = portsMenu
    mainMenu.addItem(portsMenuItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func quitFromMenu() {
    PortManagerAppLifecycle.quit()
  }

  @objc private func refreshFromMenu() {
    NotificationCenter.default.post(name: .refreshPortsRequested, object: nil)
  }

  @objc private func killSelectedPortFromMenu() {
    NotificationCenter.default.post(name: .killSelectedPortRequested, object: nil)
  }
}

@MainActor
final class PortManagerMainWindowController: NSObject, NSWindowDelegate {
  let portStore: PortStore
  private var window: NSWindow?

  init(portStore: PortStore) {
    self.portStore = portStore
  }

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    if !window.isVisible {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func showSettings() {
    show()
    NotificationCenter.default.post(name: .showSettingsRequested, object: nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 672),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Port Manager"
    window.identifier = NSUserInterfaceItemIdentifier("main")
    window.contentViewController = NSHostingController(rootView: ContentView(store: portStore))
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("main-AppKit")
    window.minSize = NSSize(width: 980, height: 620)
    window.delegate = self
    return window
  }
}

@main
enum PortManagerAppMain {
  @MainActor private static var appDelegate: AppDelegate?

  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    appDelegate = delegate
    application.delegate = delegate
    application.run()
  }
}

extension Notification.Name {
  static let refreshPortsRequested = Notification.Name("PortManagerRefreshPortsRequested")
  static let killSelectedPortRequested = Notification.Name("PortManagerKillSelectedPortRequested")
  static let showSettingsRequested = Notification.Name("PortManagerShowSettingsRequested")
}
