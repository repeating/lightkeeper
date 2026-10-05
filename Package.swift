// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Lightkeeper", platforms: [.macOS(.v14)],
    products: [.executable(name: "Lightkeeper", targets: ["Lightkeeper"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "BeaconCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Lightkeeper", dependencies: ["BeaconCore"]),
        .executableTarget(name: "BeaconTests", dependencies: ["BeaconCore"], path: "Tests/BeaconCoreTests")
    ], swiftLanguageModes: [.v5]
)
