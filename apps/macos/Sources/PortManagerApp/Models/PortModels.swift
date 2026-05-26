import Foundation

struct ListeningPort: Identifiable, Hashable {
  let id: String
  let pid: Int
  let status: PortStatus
  let processName: String
  let user: String
  let uid: Int?
  let parentPid: Int?
  let command: String?
  let arguments: String?
  let currentDirectory: String?
  let launchOriginator: String?
  let binds: [PortBind]
  let ownershipEvidence: [String]
  let ownershipSummaryOverride: String?
  let ownershipConfidenceOverride: OwnershipConfidence?

  var title: String {
    processName.isEmpty ? "PID \(pid)" : processName
  }

  var subtitle: String {
    let ports = binds.map { "\($0.host):\($0.port)" }.joined(separator: ", ")
    let owner = user.isEmpty ? status.label : user
    return ports.isEmpty ? owner : "\(owner) - \(ports)"
  }

  var ownershipSummary: String {
    if let ownershipSummaryOverride {
      return ownershipSummaryOverride
    }
    return "\(title) owns \(binds.map { "\($0.host):\($0.port)" }.joined(separator: ", "))"
  }

  var confidence: OwnershipConfidence {
    if let ownershipConfidenceOverride {
      return ownershipConfidenceOverride
    }
    if command != nil || launchOriginator != nil {
      return .high
    }
    return .medium
  }

  var canKill: Bool {
    status == .listening && pid > 0
  }

  var primaryPort: Int? {
    binds.first?.port
  }

  var primaryBindingLabel: String {
    guard let bind = binds.first else { return "unknown port" }
    return "\(bind.host):\(bind.port)"
  }
}

enum PortStatus: String {
  case listening
  case reserved

  var label: String {
    switch self {
    case .listening:
      return "Listening"
    case .reserved:
      return "Reserved"
    }
  }
}

struct PortBind: Identifiable, Hashable {
  let id: String
  let host: String
  let port: Int
  let proto: String
  let commonPort: CommonPort?
}

struct CommonPort: Codable, Hashable {
  let name: String
  let expectedApps: [String]
}

enum OwnershipConfidence: String {
  case high = "High"
  case medium = "Medium"
}
