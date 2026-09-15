// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingleThreadCore",
    platforms: [
        .iOS("17.0"),
        .watchOS("11.0"),
        .macOS("26.5")
    ],
    products: [
        .library(name: "SingleThreadCore", targets: ["SingleThreadCore"])
    ],
    targets: [
        .target(
            name: "SingleThreadCore",
            resources: [.process("Resources")])
    ])
