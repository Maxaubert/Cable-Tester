// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CableKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CableKit", targets: ["CableKit"])],
    targets: [
        .target(name: "CableKit"),
        .testTarget(name: "CableKitTests", dependencies: ["CableKit"], resources: [.copy("Fixtures")]),
    ]
)
