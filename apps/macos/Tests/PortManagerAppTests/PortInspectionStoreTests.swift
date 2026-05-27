import Foundation
import Testing
@testable import PortManagerApp

@Test @MainActor func recordingInspectionKeepsHistoryAndLatest() {
  let defaults = UserDefaults(suiteName: "PortInspectionStoreTests-\(UUID().uuidString)")!
  let store = PortInspectionStore(userDefaults: defaults)
  let first = inspection(key: "cursor", generatedAt: Date(timeIntervalSince1970: 100))
  let second = inspection(key: "cursor", generatedAt: Date(timeIntervalSince1970: 200))

  store.record(first)
  store.record(second)

  #expect(store.inspections["cursor"]?.generatedAt == second.generatedAt)
  #expect(store.inspectionHistory["cursor"]?.map(\.generatedAt) == [first.generatedAt, second.generatedAt])
}

private func inspection(key: String, generatedAt: Date) -> PortInspection {
  PortInspection(
    key: key,
    title: "Cursor",
    generatedAt: generatedAt,
    summary: "Summary",
    details: [],
    basis: [],
    ports: [40423],
    sources: [],
    warnings: []
  )
}
