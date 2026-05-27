import Testing
@testable import PortManagerApp

@Test func menuClusterSummaryIncludesInlinePorts() {
  let cluster = PortCluster(
    id: "ai-cursor",
    title: "Cursor",
    ports: [
      listeningPort(
        processName: "Cursor Helper (Plugin)",
        command: "/Applications/Cursor.app/Contents/MacOS/Cursor",
        bind: PortBind(id: "a", host: "127.0.0.1", port: 40423, proto: "TCP", commonPort: nil, ownerPid: 1, ownerName: "Cursor Helper (Plugin)"),
        displayGroup: PortDisplayGroup(id: "ai", name: "AI", rank: 30)
      ),
      listeningPort(
        processName: "Cursor Helper (Plugin)",
        command: "/Applications/Cursor.app/Contents/MacOS/Cursor",
        bind: PortBind(id: "b", host: "127.0.0.1", port: 40589, proto: "TCP", commonPort: nil, ownerPid: 2, ownerName: "Cursor Helper (Plugin)"),
        displayGroup: PortDisplayGroup(id: "ai", name: "AI", rank: 30)
      )
    ]
  )

  #expect(menuClusterSummaryTitle(for: cluster) == "Cursor 2 ports: 40423, 40589")
}
