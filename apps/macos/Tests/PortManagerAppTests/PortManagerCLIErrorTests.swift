import Foundation
import Testing
@testable import PortManagerApp

@Test func cliJsonErrorBecomesHumanReadableNoOwnerError() {
  let stderr = Data(
    """
    {
      "schemaVersion": "2026-05-26.port-manager.cli.v1",
      "ok": false,
      "error": {
        "code": "PORT_MANAGER_NO_OWNER",
        "message": "No process owner found for port 41737"
      }
    }
    """.utf8
  )

  let error = PortManagerCLIError.fromProcessOutput(stdout: Data(), stderr: stderr, fallback: "failed")

  #expect(error.code == "PORT_MANAGER_NO_OWNER")
  #expect(error.shouldRefreshPorts)
  #expect(error.localizedDescription == "No process owner found for port 41737. The port list may be stale, so Port Manager refreshed it.")
  #expect(!error.localizedDescription.contains("\"schemaVersion\""))
}

@Test func cliPlainTextErrorStillSurfacesPlainText() {
  let stderr = Data("pnpm failed".utf8)

  let error = PortManagerCLIError.fromProcessOutput(stdout: Data(), stderr: stderr, fallback: "failed")

  #expect(error.code == nil)
  #expect(!error.shouldRefreshPorts)
  #expect(error.localizedDescription == "pnpm failed")
}
