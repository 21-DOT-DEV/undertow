// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "undertow",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-tuist.git", exact: "4.169.1"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.2.1"),
    ],
    targets: []
)
