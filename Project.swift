import ProjectDescription

let project = Project(
    name: "Undertow",
    packages: [
        .package(path: "."),
//        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
//        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
//        .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: "main"),
    ],
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Resources/Project/Debug.xcconfig"),
            .release(name: "Release", xcconfig: "Resources/Project/Release.xcconfig")
        ]
    ),
    targets: [
        // MARK: - Shared Framework

        .target(
            name: "UndertowKit",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.21.UndertowKit",
            deploymentTargets: .macOS("26.0"),
            sources: ["Sources/UndertowKit/**"],
            dependencies: [
                .package(product: "SwiftSyntax"),
                .package(product: "SwiftParser")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowKit/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowKit/Release.xcconfig")
                ]
            )
        ),

        // MARK: - Communication Bridge

        .target(
            name: "UndertowBridge",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.21.Undertow.Bridge",
            deploymentTargets: .macOS("26.0"),
            sources: ["Sources/UndertowBridge/**"],
            entitlements: "Resources/UndertowBridge/UndertowBridge.entitlements",
            dependencies: [
                .target(name: "UndertowKit")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowBridge/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowBridge/Release.xcconfig")
                ]
            )
        ),

        // MARK: - Background Agent

        .target(
            name: "UndertowHelper",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.21.Undertow.Helper",
            deploymentTargets: .macOS("26.0"),
            sources: ["Sources/UndertowHelper/**"],
            entitlements: "Resources/UndertowHelper/UndertowHelper.entitlements",
            dependencies: [
                .target(name: "UndertowKit"),
                .package(product: "MCP"),
                .package(product: "IndexStoreDB")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowHelper/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowHelper/Release.xcconfig")
                ]
            )
        ),

        // MARK: - Source Editor Extension

        .target(
            name: "UndertowExtension",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "dev.21.Undertow.Extension",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .file(path: "Resources/UndertowExtension/Info.plist"),
            sources: ["Sources/UndertowExtension/**"],
            entitlements: "Resources/UndertowExtension/UndertowExtension.entitlements",
            dependencies: [
                .target(name: "UndertowKit"),
                .sdk(name: "XcodeKit", type: .framework)
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowExtension/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowExtension/Release.xcconfig")
                ]
            )
        ),

        // MARK: - Companion App

        .target(
            name: "Undertow",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.21.Undertow",
            deploymentTargets: .macOS("26.0"),
            sources: ["Sources/Undertow/**"],
            resources: [
                "Resources/Undertow/Assets.xcassets/**",
                "Resources/Undertow/Preview Content/**"
            ],
            entitlements: "Resources/Undertow/Undertow.entitlements",
            dependencies: [
                .target(name: "UndertowKit"),
                .target(name: "UndertowExtension")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/Undertow/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/Undertow/Release.xcconfig")
                ]
            )
        ),

        // MARK: - Tests

        .target(
            name: "UndertowTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.21.UndertowTests",
            deploymentTargets: .macOS("26.0"),
            sources: ["Sources/UndertowTests/**"],
            dependencies: [
                .target(name: "Undertow"),
                .target(name: "UndertowKit")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowTests/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowTests/Release.xcconfig")
                ]
            )
        )
    ]
)
