import ProjectDescription

let project = Project(
    name: "Undertow",
    packages: [
        .package(path: ".")
    ],
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Resources/Project/Debug.xcconfig"),
            .release(name: "Release", xcconfig: "Resources/Project/Release.xcconfig")
        ]
    ),
    targets: [
        // MARK: - Companion App

        .target(
            name: "Undertow",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.21.Undertow",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/Undertow/**"],
            resources: [
                "Resources/Undertow/Assets.xcassets/**",
                "Resources/Undertow/Preview Content/**"
            ],
            entitlements: "Resources/Undertow/Undertow.entitlements",
            dependencies: [],
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
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/UndertowTests/**"],
            dependencies: [.target(name: "Undertow")],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowTests/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowTests/Release.xcconfig")
                ]
            )
        )
    ]
)
