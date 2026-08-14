// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingleThreadCore",
    platforms: [
        .iOS("26.5"),
        .watchOS("26.5"),
        .macOS("26.5"),
        .visionOS("26.5"),
    ],
    products: [
        .library(name: "SingleThreadCore", targets: ["SingleThreadCore"]),
    ],
    targets: [
        .target(name: "SingleThreadCore"),
    ])
