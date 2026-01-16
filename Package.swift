// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CodexMonitor",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "CodexMonitor", targets: ["CodexMonitor"])
  ],
  dependencies: [
    .package(name: "VeloxRuntimeWry", path: "../../velox")
  ],
  targets: [
    .executableTarget(
      name: "CodexMonitor",
      dependencies: [
        .product(name: "VeloxRuntime", package: "VeloxRuntimeWry"),
        .product(name: "VeloxRuntimeWry", package: "VeloxRuntimeWry"),
        .product(name: "VeloxPlugins", package: "VeloxRuntimeWry")
      ]
    )
  ]
)
