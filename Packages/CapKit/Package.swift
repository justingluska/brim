// swift-tools-version: 5.9
import PackageDescription

// CapKit is the Foundation-only client for Cap's mobile API (`/api/mobile`).
// It has no UIKit/SwiftUI dependency so it builds and tests on Linux too,
// which is how it is checked on the agent box before every push.
let package = Package(
    name: "CapKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CapKit", targets: ["CapKit"]),
    ],
    targets: [
        .target(name: "CapKit"),
        .testTarget(name: "CapKitTests", dependencies: ["CapKit"], resources: [.copy("Fixtures")]),
    ]
)
