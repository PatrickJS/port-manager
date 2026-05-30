import Darwin
import Foundation

final class PortManagerSingleInstance {
  private static let distributedShowMainWindowName = Notification.Name("dev.patrickjs.PortManager.showMainWindow")

  private let lockURL: URL
  private let fallbackLockURL: URL?
  private var fileDescriptor: Int32 = -1

  init(lockURL: URL = PortManagerSingleInstance.defaultLockURL(), fallbackLockURL: URL? = PortManagerSingleInstance.fallbackLockURL()) {
    self.lockURL = lockURL
    self.fallbackLockURL = fallbackLockURL
  }

  deinit {
    release()
  }

  @discardableResult
  func acquire() -> Bool {
    guard fileDescriptor == -1 else { return true }

    switch tryAcquire(lockURL) {
    case let .acquired(fileDescriptor):
      self.fileDescriptor = fileDescriptor
      writeCurrentPID(to: fileDescriptor)
      return true
    case .alreadyRunning:
      return false
    case .unavailable:
      guard let fallbackLockURL else { return false }
      switch tryAcquire(fallbackLockURL) {
      case let .acquired(fileDescriptor):
        self.fileDescriptor = fileDescriptor
        writeCurrentPID(to: fileDescriptor)
        return true
      case .alreadyRunning, .unavailable:
        return false
      }
    }
  }

  func release() {
    guard fileDescriptor != -1 else { return }
    flock(fileDescriptor, LOCK_UN)
    close(fileDescriptor)
    fileDescriptor = -1
  }

  static func requestMainWindowFromRunningInstance() {
    DistributedNotificationCenter.default().postNotificationName(
      distributedShowMainWindowName,
      object: nil,
      userInfo: nil,
      deliverImmediately: true
    )
  }

  static func addMainWindowObserver(_ observer: Any, selector: Selector) {
    DistributedNotificationCenter.default().addObserver(
      observer,
      selector: selector,
      name: distributedShowMainWindowName,
      object: nil
    )
  }

  private static func defaultLockURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("PortManager")
      .appendingPathComponent("PortManager.lock")
  }

  private static func fallbackLockURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("dev.patrickjs.PortManager.lock")
  }

  private enum LockAttempt {
    case acquired(Int32)
    case alreadyRunning
    case unavailable
  }

  private func tryAcquire(_ url: URL) -> LockAttempt {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      return .unavailable
    }

    let fileDescriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fileDescriptor >= 0 else { return .unavailable }

    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(fileDescriptor)
      return .alreadyRunning
    }

    return .acquired(fileDescriptor)
  }

  private func writeCurrentPID(to fileDescriptor: Int32) {
    let data = Data("\(getpid())\n".utf8)
    ftruncate(fileDescriptor, 0)
    lseek(fileDescriptor, 0, SEEK_SET)
    data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      _ = Darwin.write(fileDescriptor, baseAddress, buffer.count)
    }
  }
}
