import ProjectDescription

let project = Project(
    name: "Undertow",
    packages: [
        .package(path: "."),
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
            product: .staticLibrary,
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
            scripts: [
                .post(
                    script: """
                    INSTALL_DIR="$HOME/Library/Application Support/Undertow/bin"
                    SYMLINK_DIR="$HOME/.undertow/bin"
                    mkdir -p "$INSTALL_DIR" "$SYMLINK_DIR"
                    cp "$BUILT_PRODUCTS_DIR/UndertowHelper" "$INSTALL_DIR/UndertowHelper"
                    codesign --force --sign - "$INSTALL_DIR/UndertowHelper"
                    ln -sf "$INSTALL_DIR/UndertowHelper" "$SYMLINK_DIR/UndertowHelper"
                    echo "Installed UndertowHelper to $INSTALL_DIR (symlinked from $SYMLINK_DIR)"
                    """,
                    name: "Install UndertowHelper",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .target(name: "UndertowKit"),
                .package(product: "MCP"),
                .package(product: "IndexStoreDB"),
                .package(product: "Subprocess")
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
                base: [
                    "CODE_SIGN_IDENTITY": "Apple Development"
                ],
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
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true
            ]),
            sources: ["Sources/Undertow/**"],
            resources: [
                "Resources/Undertow/Assets.xcassets/**",
                "Resources/Undertow/Preview Content/**"
            ],
            entitlements: "Resources/Undertow/Undertow.entitlements",
            scripts: [
                .post(
                    script: """
                    # Embed helper executables into the app bundle (Contents/Helpers/)
                    # Tuist does not auto-embed .commandLineTool targets, so we copy manually.
                    # Pattern borrowed from CopilotForXcode (which uses Contents/Applications/).
                    HELPERS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
                    mkdir -p "$HELPERS_DIR"

                    for TOOL in UndertowHelper UndertowBridge; do
                        SRC="${BUILT_PRODUCTS_DIR}/${TOOL}"
                        if [ -f "$SRC" ]; then
                            cp "$SRC" "$HELPERS_DIR/$TOOL"
                            codesign --force --sign "${CODE_SIGN_IDENTITY:-"-"}" "$HELPERS_DIR/$TOOL"
                            echo "Embedded $TOOL in app bundle"
                        else
                            echo "warning: $TOOL not found at $SRC" >&2
                        fi
                    done
                    """,
                    name: "Embed Helper Executables",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .target(name: "UndertowKit"),
                .target(name: "UndertowExtension"),
                .target(name: "UndertowHelper"),
                .target(name: "UndertowBridge")
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "Apple Development"
                ],
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
                .target(name: "UndertowKit"),
                .package(product: "Subprocess")
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "Resources/UndertowTests/Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "Resources/UndertowTests/Release.xcconfig")
                ]
            )
        )
    ],
    schemes: [
        .scheme(
            name: "UndertowTests",
            shared: true,
            buildAction: .buildAction(targets: ["UndertowKit", "UndertowTests"]),
            testAction: .targets(["UndertowTests"])
        )
    ]
)
