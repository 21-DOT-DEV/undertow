import ApplicationServices
import Foundation
import Observation
import UndertowKit

/// Coordinates configuration operations and helper installation.
///
/// Delegates config I/O to `ConfigManager` in UndertowKit. Without the sandbox,
/// no bookmark management is needed — the app reads/writes files directly.
@Observable
final class SetupManager {
    let configManager = ConfigManager()

    // MARK: - Setup Status

    func getSetupStatus() -> SetupStatusReport {
        configManager.getSetupStatus()
    }

    // MARK: - Project Config

    func addProject(path: String, target: ConfigTarget = .xcode) throws {
        try configManager.addProject(path: path, target: target)
    }

    func removeProject(path: String, target: ConfigTarget = .xcode) throws {
        try configManager.removeProject(path: path, target: target)
    }

    // MARK: - MCP Server Verification

    func verifyProject(path projectPath: String) -> VerificationResult {
        configManager.verifyProject(path: projectPath)
    }

    // MARK: - Helper Installation

    func ensureHelperInstalled() throws {
        let bundledHelper = Bundle.main.bundlePath + "/Contents/Helpers/UndertowHelper"
        let fm = FileManager.default

        try fm.createDirectory(at: configManager.installDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: bundledHelper) {
            if fm.fileExists(atPath: configManager.helperPath.path) {
                try fm.removeItem(at: configManager.helperPath)
            }
            try fm.copyItem(atPath: bundledHelper, toPath: configManager.helperPath.path)

            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", configManager.helperPath.path]
            try sign.run()
            sign.waitUntilExit()
        } else if !fm.fileExists(atPath: configManager.helperPath.path) {
            throw SetupError.helperNotFound(
                "UndertowHelper not found in app bundle or install directory"
            )
        }

        try fm.createDirectory(at: configManager.symlinkDir, withIntermediateDirectories: true)

        if (try? fm.attributesOfItem(atPath: configManager.symlinkPath.path)) != nil {
            try fm.removeItem(at: configManager.symlinkPath)
        }

        try fm.createSymbolicLink(
            atPath: configManager.symlinkPath.path,
            withDestinationPath: configManager.helperPath.path
        )
    }

    // MARK: - Accessibility

    func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }
}

// MARK: - Errors

enum SetupError: LocalizedError {
    case helperNotFound(String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound(let message): message
        }
    }
}
