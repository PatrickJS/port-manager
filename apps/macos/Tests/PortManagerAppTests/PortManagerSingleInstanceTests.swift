import Foundation
import Testing
@testable import PortManagerApp

@Test func singleInstanceLockRejectsSecondOwnerUntilFirstReleases() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("PortManagerSingleInstanceTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let lockURL = directory.appendingPathComponent("PortManager.lock")
  let first = PortManagerSingleInstance(lockURL: lockURL, fallbackLockURL: nil)
  let second = PortManagerSingleInstance(lockURL: lockURL, fallbackLockURL: nil)

  #expect(first.acquire())
  #expect(!second.acquire())

  first.release()

  #expect(second.acquire())
}
