// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PortManagerMac",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "PortManager", targets: ["PortManagerApp"]),
    .executable(name: "PortManagerLauncher", targets: ["PortManagerLauncher"])
  ],
  targets: [
    .executableTarget(
      name: "PortManagerApp",
      path: "Sources/PortManagerApp"
    ),
    .executableTarget(
      name: "PortManagerLauncher",
      path: "Sources/PortManagerLauncher"
    ),
    .testTarget(
      name: "PortManagerAppTests",
      dependencies: ["PortManagerApp"],
      path: "Tests/PortManagerAppTests"
    )
  ]
)
