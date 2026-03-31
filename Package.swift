// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "undertow",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-tuist.git", exact: "4.169.1")
    ],
    targets: []
)
