import AppKit

@MainActor
final class PortManagerStatusMenuController: NSObject, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private let menu = NSMenu()
  let portStore: PortStore
  private weak var mainWindowController: PortManagerMainWindowController?
  private let groupingRulesStore = PortGroupingRulesStore()
  private var menuActions: [String: () -> Void] = [:]

  init(portStore: PortStore, mainWindowController: PortManagerMainWindowController?) {
    self.portStore = portStore
    self.mainWindowController = mainWindowController
    super.init()
  }

  func start() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem
    statusItem.isVisible = true
    if let button = statusItem.button {
      button.image = Self.makePortManagerIcon()
      button.imagePosition = .imageOnly
      button.title = ""
      button.toolTip = "Port Manager"
      button.setAccessibilityLabel("Port Manager")
    }

    menu.delegate = self
    statusItem.menu = menu
    renderMenu()
    refresh(showProgress: true)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(refreshRequested),
      name: .refreshPortsRequested,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(groupingRulesChanged),
      name: .groupingRulesChanged,
      object: nil
    )
  }

  private static func makePortManagerIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 23, height: 19))
    image.lockFocus()

    NSColor.black.setStroke()
    NSColor.black.setFill()

    let border = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 18, height: 14), xRadius: 3.4, yRadius: 3.4)
    border.lineWidth = 1.9
    border.stroke()

    let barWidth: CGFloat = 2.2
    let baselineY: CGFloat = 5
    let barCornerRadius: CGFloat = 0.9
    let bars: [(x: CGFloat, height: CGFloat)] = [
      (6.2, 4.6),
      (10.3, 7.2),
      (14.4, 9.6)
    ]

    for bar in bars {
      let rect = NSRect(x: bar.x, y: baselineY, width: barWidth, height: bar.height)
      NSBezierPath(roundedRect: rect, xRadius: barCornerRadius, yRadius: barCornerRadius).fill()
    }

    let axis = NSBezierPath()
    axis.lineWidth = 1.7
    axis.lineCapStyle = .round
    axis.move(to: NSPoint(x: 5, y: baselineY))
    axis.line(to: NSPoint(x: 17.8, y: baselineY))
    axis.stroke()

    let slash = NSBezierPath()
    slash.lineWidth = 2.4
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: 5.2, y: 15.4))
    slash.line(to: NSPoint(x: 18.2, y: 3.6))
    slash.stroke()

    image.unlockFocus()
    image.isTemplate = true
    image.accessibilityDescription = "Port Manager"
    return image
  }

  func menuWillOpen(_ menu: NSMenu) {
    refresh(showProgress: true)
  }

  @objc private func refreshRequested() {
    refresh(showProgress: true)
  }

  @objc private func groupingRulesChanged() {
    groupingRulesStore.reload()
    renderMenu()
  }

  private func refresh(showProgress: Bool) {
    if showProgress {
      renderMenu(showRefreshing: true)
    }
    Task {
      await portStore.refresh(force: true)
      renderMenu()
    }
  }

  private func renderMenu(showRefreshing: Bool = false) {
    groupingRulesStore.reload()
    menuActions.removeAll()
    menu.removeAllItems()

    if showRefreshing || portStore.isLoading {
      let title = portStore.ports.isEmpty ? "Scanning Ports..." : "Refreshing..."
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      if !portStore.ports.isEmpty {
        menu.addItem(.separator())
      }
    }

    if portStore.ports.isEmpty {
      if let errorMessage = portStore.errorMessage ?? portStore.lastRefreshError {
        let item = NSMenuItem(title: truncated(errorMessage), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      } else if !showRefreshing && !portStore.isLoading {
      let item = NSMenuItem(title: "No Open Ports", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      }
    } else {
      addPortSections(to: menu)
      if let errorMessage = portStore.lastRefreshError {
        menu.addItem(.separator())
        let item = NSMenuItem(title: truncated("Last refresh failed: \(errorMessage)"), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())
    menu.addItem(actionItem(title: "Open Port Manager") {
      self.mainWindowController?.show()
    })
    menu.addItem(actionItem(title: "Settings") {
      self.mainWindowController?.showSettings()
    })
    menu.addItem(actionItem(title: "Refresh Ports") { [weak self] in
      self?.refresh(showProgress: true)
    })
    menu.addItem(.separator())
    menu.addItem(actionItem(title: "Quit Port Manager") {
      PortManagerAppLifecycle.quit()
    })

  }

  private func addPortSections(to menu: NSMenu) {
    let sections = menuSections(for: portStore.ports)
    let regularSections = sections.filter { !$0.isSafeToIgnore }
    let safeSections = sections.filter(\.isSafeToIgnore)

    for (index, section) in regularSections.enumerated() {
      if index > 0 {
        menu.addItem(.separator())
      }
      addSection(section, to: menu)
    }

    if !safeSections.isEmpty {
      menu.addItem(.separator())
      for section in safeSections {
        let item = NSMenuItem(title: sectionSummaryTitle(for: section), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        addSection(section, to: submenu, includeHeader: false)
        item.submenu = submenu
        menu.addItem(item)
      }
    }
  }

  private func addSection(_ section: StatusMenuSection, to menu: NSMenu, includeHeader: Bool = true) {
    if includeHeader {
      let header = NSMenuItem(title: section.name, action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
    }

    for cluster in section.clusters {
      if cluster.isSinglePort, let port = cluster.firstPort {
        menu.addItem(portMenuItem(for: port))
      } else {
        let item = NSMenuItem(title: truncated(menuClusterSummaryTitle(for: cluster)), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for port in cluster.ports {
          submenu.addItem(portMenuItem(for: port))
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Copy Ports") {
          self.copy(cluster.portList)
        })
        submenu.addItem(actionItem(title: "Open Port Manager") {
          self.mainWindowController?.show()
        })
        item.submenu = submenu
        menu.addItem(item)
      }
    }
  }

  private func portMenuItem(for port: ListeningPort) -> NSMenuItem {
    let item = NSMenuItem(title: menuTitle(for: port), action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let titleItem = NSMenuItem(title: port.title, action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    submenu.addItem(titleItem)

    if let groupReason = port.groupReason {
      let reasonItem = NSMenuItem(title: truncated(groupReason), action: nil, keyEquivalent: "")
      reasonItem.isEnabled = false
      submenu.addItem(reasonItem)
    }

    for bind in port.binds {
      let bindItem = NSMenuItem(title: bindingTitle(for: bind), action: nil, keyEquivalent: "")
      bindItem.isEnabled = false
      submenu.addItem(bindItem)
    }

    let ownerTitle = port.ownerCount == 1 ? "PID \(port.pid)" : "\(port.ownerCount) owners"
    let ownerItem = NSMenuItem(title: ownerTitle, action: nil, keyEquivalent: "")
    ownerItem.isEnabled = false
    submenu.addItem(ownerItem)

    if let commonPort = port.binds.first?.commonPort {
      let commonItem = NSMenuItem(title: commonPort.name, action: nil, keyEquivalent: "")
      commonItem.isEnabled = false
      submenu.addItem(commonItem)
    }

    submenu.addItem(.separator())
    submenu.addItem(actionItem(title: port.binds.count == 1 ? "Copy Binding" : "Copy Bindings") {
      self.copy(port.bindingLabels)
    })
    submenu.addItem(actionItem(title: "Open Port Manager") {
      self.mainWindowController?.show()
    })
    if port.canKill {
      let killItem = actionItem(title: "Kill Port") { [weak self] in
        self?.confirmAndKill(port)
      }
      killItem.attributedTitle = NSAttributedString(
        string: "Kill Port",
        attributes: [.foregroundColor: NSColor.systemRed]
      )
      submenu.addItem(killItem)
    }

    item.submenu = submenu
    return item
  }

  private func confirmAndKill(_ port: ListeningPort) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Kill Port?"
    alert.informativeText = "Send SIGTERM to \(port.killDescription)."
    alert.addButton(withTitle: "Kill Port")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    Task {
      await portStore.kill(port)
      renderMenu()
      if let errorMessage = portStore.errorMessage {
        showError(errorMessage)
      }
    }
  }

  private func showError(_ message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Port Manager Failed"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func actionItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
    let key = UUID().uuidString
    menuActions[key] = action
    let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = key
    return item
  }

  @objc private func performMenuAction(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String else { return }
    menuActions[key]?()
  }

  private func menuSections(for ports: [ListeningPort]) -> [StatusMenuSection] {
    let groups = Dictionary(grouping: ports) { port in
      configuredDisplayGroup(for: port, rules: groupingRulesStore.rules, groups: groupingRulesStore.groups)
    }
    return groups
      .map { group, ports in
        StatusMenuSection(group: group, ports: ports.sorted(by: sortPorts), groupingRules: groupingRulesStore.rules)
      }
      .sorted { lhs, rhs in
        if lhs.rank != rhs.rank {
          return lhs.rank < rhs.rank
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  private func sortPorts(_ lhs: ListeningPort, _ rhs: ListeningPort) -> Bool {
    (lhs.primaryPort ?? 0) < (rhs.primaryPort ?? 0)
  }

  private func menuTitle(for port: ListeningPort) -> String {
    truncated("\(port.primaryPort.map(String.init) ?? "?") - \(port.title)")
  }

  private func bindingTitle(for bind: PortBind) -> String {
    if let ownerLabel = bind.ownerLabel {
      return truncated("\(bind.host):\(bind.port) - \(ownerLabel)")
    }
    return truncated("\(bind.host):\(bind.port)")
  }

  private func sectionSummaryTitle(for section: StatusMenuSection) -> String {
    if section.portList.isEmpty {
      return "\(section.name) \(section.ports.count) ports"
    }
    return truncated("\(section.name) \(section.ports.count) ports: \(section.portList)")
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  private func truncated(_ value: String) -> String {
    if value.count <= 42 {
      return value
    }
    return "\(value.prefix(41))..."
  }
}

private struct StatusMenuSection: Identifiable {
  let id: String
  let name: String
  let rank: Int
  let ports: [ListeningPort]
  let clusters: [PortCluster]
  var portList: String {
    ports
      .compactMap(\.primaryPort)
      .map(String.init)
      .joined(separator: ", ")
  }

  var isSafeToIgnore: Bool {
    id == "os-apple" || id == "system"
  }

  init(group: PortDisplayGroup, ports: [ListeningPort], groupingRules: [PortGroupingRule]) {
    id = group.id
    name = group.name
    rank = group.rank
    self.ports = ports
    clusters = portClusters(for: ports, namespace: group.id, rules: groupingRules)
  }
}
