// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "HealthSyncCore",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(name: "HealthSyncCore", targets: ["HealthSyncCore"])
  ],
  targets: [
    .target(name: "HealthSyncCore"),
    .testTarget(
      name: "HealthSyncCoreTests",
      dependencies: ["HealthSyncCore"],
      resources: [.process("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
