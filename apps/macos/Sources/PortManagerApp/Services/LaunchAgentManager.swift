import Darwin
import Foundation
import Observation

enum LaunchAgentTarget: String, CaseIterable, Identifiable {
  case currentApp
  case localDist

  var id: String { rawValue }

  var title: String {
    switch self {
    case .currentApp:
      return "This app"
    case .localDist:
      return "Local dist build"
    }
  }

  var detail: String {
    switch self {
    case .currentApp:
      return "Use the current app bundle. This is the right choice for released builds."
    case .localDist:
      return "Use the repo's dist/PortManager.app bundle. This is useful while developing from source."
    }
  }
}

@MainActor
@Observable
final class LaunchAgentSettingsStore {
  var isEnabled = false
  var selectedTarget: LaunchAgentTarget = .currentApp
  var resolvedTargetPath = ""
  var launcherPath = ""
  var launchctlStatus = "Not installed"
  var stdoutLog = ""
  var stderrLog = ""
  var statusMessage: String?
  var errorMessage: String?

  private let manager = LaunchAgentManager()

  init() {
    reload()
  }

  func reload() {
    selectedTarget = manager.installedTarget ?? manager.selectedTarget
    isEnabled = manager.isInstalled
    resolvedTargetPath = manager.targetAppURL(for: selectedTarget)?.path ?? "Unavailable"
    refreshDiagnostics()
  }

  func refreshDiagnostics() {
    let diagnostics = manager.diagnostics(target: selectedTarget)
    launcherPath = diagnostics.launcherPath ?? "Unavailable"
    launchctlStatus = diagnostics.launchctlStatus
    stdoutLog = diagnostics.stdoutLog
    stderrLog = diagnostics.stderrLog
  }

  func setEnabled(_ enabled: Bool) async {
    errorMessage = nil
    statusMessage = nil
    do {
      if enabled {
        try manager.install(target: selectedTarget)
        statusMessage = "Port Manager will start at login and relaunch if it exits."
      } else {
        try manager.uninstall()
        statusMessage = "Startup agent removed."
      }
      reload()
    } catch {
      errorMessage = error.localizedDescription
      reload()
    }
  }

  func setTarget(_ target: LaunchAgentTarget) async {
    selectedTarget = target
    manager.selectedTarget = target
    resolvedTargetPath = manager.targetAppURL(for: target)?.path ?? "Unavailable"
    refreshDiagnostics()
    guard isEnabled else { return }
    await setEnabled(true)
  }
}

struct LaunchAgentDiagnostics {
  let launcherPath: String?
  let launchctlStatus: String
  let stdoutLog: String
  let stderrLog: String
}

struct LaunchAgentManager {
  private static let targetDefaultsKey = "PortManagerLaunchAgentTarget"
  private static let label = "dev.patrickjs.PortManager"
  private static let processName = "PortManager"

  private let config: PortManagerAppConfig
  private let fileManager = FileManager.default

  init(config: PortManagerAppConfig = .load()) {
    self.config = config
  }

  var selectedTarget: LaunchAgentTarget {
    get {
      let value = UserDefaults.standard.string(forKey: Self.targetDefaultsKey)
      return value.flatMap(LaunchAgentTarget.init(rawValue:)) ?? .currentApp
    }
    nonmutating set {
      UserDefaults.standard.set(newValue.rawValue, forKey: Self.targetDefaultsKey)
    }
  }

  var isInstalled: Bool {
    fileManager.fileExists(atPath: plistURL.path)
  }

  var installedTarget: LaunchAgentTarget? {
    guard let installedAppPath else { return nil }
    if let localDistPath = targetAppURL(for: .localDist)?.standardizedFileURL.path,
       installedAppPath == localDistPath {
      return .localDist
    }
    if let currentAppPath = targetAppURL(for: .currentApp)?.standardizedFileURL.path,
       installedAppPath == currentAppPath {
      return .currentApp
    }
    return nil
  }

  func targetAppURL(for target: LaunchAgentTarget) -> URL? {
    switch target {
    case .currentApp:
      return currentAppBundleURL()
    case .localDist:
      return URL(fileURLWithPath: config.repoRoot)
        .appendingPathComponent("dist")
        .appendingPathComponent("PortManager.app")
    }
  }

  func install(target: LaunchAgentTarget) throws {
    guard let appURL = targetAppURL(for: target), fileManager.fileExists(atPath: appURL.path) else {
      throw LaunchAgentError.missingAppBundle(target.title)
    }
    let launcherURL = launcherURL(for: appURL)
    guard fileManager.fileExists(atPath: launcherURL.path) else {
      throw LaunchAgentError.missingLauncher
    }

    try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    try Data().write(to: stdoutLogURL, options: .atomic)
    try Data().write(to: stderrLogURL, options: .atomic)
    let data = try PropertyListSerialization.data(fromPropertyList: plist(appURL: appURL), format: .xml, options: 0)
    try data.write(to: plistURL, options: .atomic)

    try? runLaunchctl(["bootout", guiDomain, plistURL.path])
    try runLaunchctl(["bootstrap", guiDomain, plistURL.path])
    try? runLaunchctl(["kickstart", "-k", "\(guiDomain)/\(Self.label)"])
    selectedTarget = target
  }

  func uninstall() throws {
    try? runLaunchctl(["bootout", guiDomain, plistURL.path])
    if fileManager.fileExists(atPath: plistURL.path) {
      try fileManager.removeItem(at: plistURL)
    }
  }

  func diagnostics(target: LaunchAgentTarget) -> LaunchAgentDiagnostics {
    let appURL = targetAppURL(for: target)
    let launcher = appURL.map(launcherURL(for:))
    return LaunchAgentDiagnostics(
      launcherPath: launcher?.path,
      launchctlStatus: launchctlSummary(),
      stdoutLog: tailLog(stdoutLogURL),
      stderrLog: tailLog(stderrLogURL)
    )
  }

  private var launchAgentsDirectory: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("LaunchAgents")
  }

  private var logsDirectory: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("Logs")
  }

  private var plistURL: URL {
    launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
  }

  private var stdoutLogURL: URL {
    logsDirectory.appendingPathComponent("PortManager.launchd.out.log")
  }

  private var stderrLogURL: URL {
    logsDirectory.appendingPathComponent("PortManager.launchd.err.log")
  }

  private var installedAppPath: String? {
    guard let data = try? Data(contentsOf: plistURL),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let arguments = plist["ProgramArguments"] as? [String],
          arguments.count >= 2
    else {
      return nil
    }
    return URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
  }

  private var guiDomain: String {
    "gui/\(getuid())"
  }

  private func plist(appURL: URL) -> [String: Any] {
    [
      "Label": Self.label,
      "ProgramArguments": [
        launcherURL(for: appURL).path,
        appURL.path,
        Self.processName,
      ],
      "RunAtLoad": true,
      "KeepAlive": true,
      "StandardOutPath": stdoutLogURL.path,
      "StandardErrorPath": stderrLogURL.path,
    ]
  }

  private func currentAppBundleURL() -> URL? {
    var url = Bundle.main.bundleURL
    while url.path != "/" && url.pathExtension != "app" {
      url.deleteLastPathComponent()
    }
    return url.pathExtension == "app" ? url : nil
  }

  private func launcherURL(for appURL: URL) -> URL {
    appURL
      .appendingPathComponent("Contents")
      .appendingPathComponent("MacOS")
      .appendingPathComponent("PortManagerLauncher")
  }

  private func launchctlSummary() -> String {
    guard isInstalled else { return "Not installed" }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", "\(guiDomain)/\(Self.label)"]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return error.localizedDescription
    }

    let data = process.terminationStatus == 0
      ? stdout.fileHandleForReading.readDataToEndOfFile()
      : stderr.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let lines = text
      .split(separator: "\n")
      .map(String.init)
      .filter { line in
        line.contains("state =")
          || line.contains("program =")
          || line.contains("pid =")
          || line.contains("last exit code =")
          || line.contains("last terminating signal =")
      }
    return lines.isEmpty ? "Installed" : lines.joined(separator: "\n")
  }

  private func tailLog(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8),
          !text.isEmpty
    else {
      return "No log output."
    }

    let lines = text.split(separator: "\n").suffix(12)
    return lines.joined(separator: "\n")
  }

  private func runLaunchctl(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let data = stderr.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw LaunchAgentError.launchctlFailed(message ?? "launchctl exited with \(process.terminationStatus)")
    }
  }
}

enum LaunchAgentError: LocalizedError {
  case missingAppBundle(String)
  case missingLauncher
  case launchctlFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingAppBundle(let target):
      return "\(target) app bundle does not exist yet."
    case .missingLauncher:
      return "PortManagerLauncher is missing from the app bundle."
    case .launchctlFailed(let message):
      return message
    }
  }
}
