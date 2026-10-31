// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScooterCore",
    platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS(.v15)],
    products: [.library(name: "ScooterCore", targets: ["ScooterCore"])],
    targets: [
        .target(name: "ScooterCore"),
        .testTarget(name: "ScooterCoreTests", dependencies: ["ScooterCore"])
    ]
)
