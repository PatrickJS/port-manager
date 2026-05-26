// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PortManagerMac",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "PortManager", targets: ["PortManagerApp"])
  ],
  targets: [
    .executableTarget(
      name: "PortManagerApp",
      path: "Sources/PortManagerApp"
    )
  ]
)
