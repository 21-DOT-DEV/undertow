import ApplicationServices
import Foundation
import Observation
import UndertowKit

/// Coordinates configuration operations and helper installation.
///
/// The app is sandboxed (App Store distribution). Filesystem access outside the
/// sandbox is granted via a security—scoped bookmark to the user's home directory.
/// The user grants access once via the Permissions tab; the bookmark persists
/// across launches.
@Observable
final class SetupManager {
    let configManager = ConfigManager()
    let bookmarkManager: BookmarkManager

    /// Convenience accessor for the current bookmark access state.
    var accessState: BookmarkManager.AccessState {
        bookmarkManager.accessState
    }

    init() {
        // Use .standard (sandbox container) — NOT the app group suite.
        // The app group container lives outside the sandbox and triggers the
        // "access data from other apps" dialog. Bookmark data is only needed
        // by the main app, so .standard is sufficient.
        self.bookmarkManager = BookmarkManager(defaults: .standard)
    }

    // MARK: - Bookmark Management

    /// Restore a previously stored bookmark on app launch.
    func restoreBookmark() {
        bookmarkManager.restoreBookmark()
    }

    /// Store bookmark data for a user-selected URL and start accessing it.
    func grantAccess(to url: URL) {
        try? bookmarkManager.storeAndAccess(url: url)
    }

    /// Revoke stored access and remove the bookmark.
    func revokeAccess() {
        bookmarkManager.revokeAccess()
    }

    // MARK: - Setup Status

    func getSetupStatus() -> SetupStatusReport {
        guard accessState == .accessGranted else {
            return SetupStatusReport(
                helperInstalled: false,
                symlinkValid: false,
                xcodeConfiguredProjects: [],
                claudeCodeConfiguredProjects: []
            )
        }
        return configManager.getSetupStatus()
    }

    // MARK: - Project Config

    func addProject(path: String) throws {
        guard accessState == .accessGranted else { throw SetupError.noFilesystemAccess }
        try configManager.addProject(path: path, target: .xcode)
    }

    func removeProject(path: String) throws {
        guard accessState == .accessGranted else { throw SetupError.noFilesystemAccess }
        try configManager.removeProject(path: path, target: .xcode)
    }

    // MARK: - MCP Server Verification

    func verifyProject(path projectPath: String) -> VerificationResult {
        guard accessState == .accessGranted else {
            return VerificationResult(success: false, message: "No filesystem access")
        }
        return configManager.verifyProject(path: projectPath)
    }

    // MARK: - Helper Installation

    func ensureHelperInstalled() throws {
        guard accessState == .accessGranted else { throw SetupError.noFilesystemAccess }

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
    case noFilesystemAccess

    var errorDescription: String? {
        switch self {
        case .helperNotFound(let message): message
        case .noFilesystemAccess:
            "Home folder access not granted. Open Permissions to grant access."
        }
    }
}
