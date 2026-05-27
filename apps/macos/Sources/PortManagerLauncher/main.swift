import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

guard arguments.count >= 2 else {
  FileHandle.standardError.write(Data("usage: PortManagerLauncher <app-path> <process-name>\n".utf8))
  exit(2)
}

let appPath = arguments[0]
let processName = arguments[1]

func run(_ executable: String, _ arguments: [String], logFailure: Bool = true) -> Int32 {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let stdout = Pipe()
  let stderr = Pipe()
  process.standardOutput = stdout
  process.standardError = stderr
  do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 && logFailure {
      let data = stderr.fileHandleForReading.readDataToEndOfFile()
      if let message = String(data: data, encoding: .utf8), !message.isEmpty {
        FileHandle.standardError.write(Data(message.utf8))
      }
    }
    return process.terminationStatus
  } catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    return 1
  }
}

func launchApp() {
  _ = run("/usr/bin/open", [appPath])
}

func isAppRunning() -> Bool {
  run("/usr/bin/pgrep", ["-x", processName], logFailure: false) == 0
}

launchApp()
Thread.sleep(forTimeInterval: 5)

while true {
  if !isAppRunning() {
    launchApp()
    Thread.sleep(forTimeInterval: 5)
  }
  Thread.sleep(forTimeInterval: 15)
}
