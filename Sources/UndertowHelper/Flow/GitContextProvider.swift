import Foundation
import Subprocess
import UndertowKit

/// Gathers git-based flow context by running git commands against the project directory.
///
/// This is the "git snapshot" layer of the hybrid flow context strategy:
/// always-fresh data gathered on demand via git CLI commands.
enum GitContextProvider {

    /// Gather a complete flow context snapshot from git state.
    ///
    /// - Parameter projectDir: The project root directory (falls back to `PROJECT_DIR` env or cwd).
    /// - Returns: A formatted, human-readable flow context string.
    static func gatherFlowContext(projectDir: String? = nil) async -> String {
        let dir = projectDir
            ?? ProcessInfo.processInfo.environment["PROJECT_DIR"]
            ?? FileManager.default.currentDirectoryPath

        var sections: [String] = []

        // Git branch
        if let branch = await git(["branch", "--show-current"], in: dir) {
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("Branch: \(trimmed)")
            }
        }

        // Uncommitted changes
        if let status = await git(["status", "--porcelain"], in: dir) {
            let lines = status.components(separatedBy: "\n").filter { !$0.isEmpty }
            if !lines.isEmpty {
                let summary = lines.prefix(15).map { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return "  \(trimmed)"
                }.joined(separator: "\n")
                var header = "Uncommitted changes (\(lines.count) file\(lines.count == 1 ? "" : "s")):"
                if lines.count > 15 {
                    header += " (showing first 15)"
                }
                sections.append("\(header)\n\(summary)")
            }
        }

        // Diff stat
        if let diffStat = await git(["diff", "--stat", "--stat-width=60"], in: dir) {
            let trimmed = diffStat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("Working tree diff:\n\(trimmed)")
            }
        }

        // Staged diff stat
        if let stagedStat = await git(["diff", "--cached", "--stat", "--stat-width=60"], in: dir) {
            let trimmed = stagedStat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("Staged for commit:\n\(trimmed)")
            }
        }

        // Recent commits
        if let log = await git(["log", "--oneline", "-5", "--no-decorate"], in: dir) {
            let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("Recent commits:\n\(trimmed)")
            }
        }

        // Recently modified source files (last 30 minutes, by mtime)
        let recentFiles = findRecentlyModifiedFiles(in: dir, minutes: 30)
        if !recentFiles.isEmpty {
            let list = recentFiles.prefix(10).map { "  \($0)" }.joined(separator: "\n")
            sections.append("Recently modified (last 30 min):\n\(list)")
        }

        if sections.isEmpty {
            return "[Undertow Flow] No activity detected in \(dir)."
        }

        return sections.joined(separator: "\n\n")
    }

    /// Build a hybrid flow context combining git snapshot with live observer data.
    ///
    /// - Parameters:
    ///   - projectDir: The project root directory.
    ///   - buildObserver: Live build log observer (used in MCP server mode).
    ///   - fileObserver: Live file system observer (used in MCP server mode).
    /// - Returns: A formatted string with git snapshot and any available observer data.
    static func gatherHybridContext(
        projectDir: String? = nil,
        buildObserver: BuildLogObserver? = nil,
        fileObserver: FileSystemObserver? = nil
    ) async -> String {
        let dir = projectDir
            ?? ProcessInfo.processInfo.environment["PROJECT_DIR"]
            ?? FileManager.default.currentDirectoryPath

        // Always gather fresh git snapshot
        var result = await gatherFlowContext(projectDir: dir)

        // Collect observer data from live observers and/or persisted state
        var extras: [String] = []

        // Build status: prefer live observer, fall back to persisted, fall back to binary mtime
        let buildStatus: BuildStatus? = await buildObserver?.latestStatus
            ?? readPersistedFlowContext()?.buildStatus
        if let build = buildStatus {
            extras.append(formatBuildStatus(build))
        } else if let buildInfo = probeBinaryBuildStatus() {
            extras.append(buildInfo)
        }

        // File activity: live FSEvents from FileSystemObserver
        if let fileObs = fileObserver {
            let events = await fileObs.recentEvents()
            if !events.isEmpty {
                let lines = events.suffix(15).map { event in
                    let relative = event.path.replacingOccurrences(of: dir + "/", with: "")
                    return "  \(event.type.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(relative)"
                }
                extras.append("File activity (\(events.count) event\(events.count == 1 ? "" : "s")):\n" + lines.joined(separator: "\n"))
            }
        }

        // Xcode state: only available from persisted context (background service)
        if let observerContext = readPersistedFlowContext() {
            if let file = observerContext.activeFile {
                let fileName = (file as NSString).lastPathComponent
                var fileInfo = "Active file: \(fileName)"
                if let line = observerContext.cursorLine {
                    fileInfo += " (line \(line))"
                }
                extras.append(fileInfo)
            }

            if let scheme = observerContext.activeScheme {
                var schemeInfo = "Scheme: \(scheme)"
                if let dest = observerContext.activeDestination {
                    schemeInfo += " → \(dest)"
                }
                extras.append(schemeInfo)
            }
        }

        if !extras.isEmpty {
            result += "\n\n[Xcode Observer Data]\n" + extras.joined(separator: "\n")
        }

        return result
    }

    /// Format a BuildStatus into a human-readable string.
    private static func formatBuildStatus(_ build: BuildStatus) -> String {
        if build.succeeded {
            return "Last build: succeeded (\(build.warningCount) warning\(build.warningCount == 1 ? "" : "s"))"
        }
        var info = "Last build: FAILED (\(build.errorCount) error\(build.errorCount == 1 ? "" : "s")"
        if build.warningCount > 0 {
            info += ", \(build.warningCount) warning\(build.warningCount == 1 ? "" : "s")"
        }
        info += ")"
        if !build.errors.isEmpty {
            let errorList = build.errors.prefix(5).map { "  - \($0)" }.joined(separator: "\n")
            info += "\n\(errorList)"
        }
        return info
    }

    // MARK: - Git Helpers

    /// Run a git command and return stdout, or nil on failure.
    static func git(_ arguments: [String], in directory: String) async -> String? {
        do {
            let result = try await Subprocess.run(
                .name("git"),
                arguments: .init(arguments),
                workingDirectory: .init(directory),
                output: .string(limit: 64 * 1024),
                error: .string(limit: 4096)
            )
            guard case .exited(0) = result.terminationStatus else { return nil }
            return result.standardOutput
        } catch {
            return nil
        }
    }

    // MARK: - File Discovery

    /// Find .swift files modified in the last N minutes under the project directory.
    static func findRecentlyModifiedFiles(in directory: String, minutes: Int) -> [String] {
        let fm = FileManager.default
        let cutoff = Date.now.addingTimeInterval(-Double(minutes * 60))
        let projectURL = URL(fileURLWithPath: directory)

        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [(path: String, date: Date)] = []

        for case let url as URL in enumerator {
            let relativePath = url.path.replacingOccurrences(of: directory + "/", with: "")
            if relativePath.hasPrefix(".build/") || relativePath.hasPrefix("DerivedData/")
                || relativePath.hasPrefix("Derived/") {
                continue
            }

            guard url.pathExtension == "swift",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate,
                  modDate > cutoff else { continue }

            results.append((path: relativePath, date: modDate))
        }

        return results.sorted { $0.date > $1.date }.map(\.path)
    }

    // MARK: - Build Status Probe

    /// Probe build status by checking the installed binary's modification time.
    ///
    /// Xcode 26 no longer writes `.xcactivitylog` files for builds, so we fall back
    /// to checking the installed binary (updated by the post-build script on every
    /// successful build).
    private static func probeBinaryBuildStatus() -> String? {
        let binaryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Undertow/bin/UndertowHelper")

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: binaryPath.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let age = Date.now.timeIntervalSince(modDate)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: modDate, relativeTo: .now)

        if age < 300 { // within 5 minutes
            return "Last successful build: \(relative)"
        } else if age < 3600 { // within 1 hour
            return "Last successful build: \(relative)"
        }
        // Older than 1 hour — not useful to report
        return nil
    }

    // MARK: - Persisted Context

    /// Read the flow context JSON persisted by the background service (if available).
    private static func readPersistedFlowContext() -> FlowContext? {
        let url = UndertowXPC.flowContextFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let context = try? JSONDecoder().decode(FlowContext.self, from: data) else {
            return nil
        }

        // Only use if reasonably fresh (within last 5 minutes)
        guard context.timestamp.timeIntervalSinceNow > -300 else { return nil }
        return context
    }

    // MARK: - Path Resolution

    /// Resolve a workspace/project path into a root directory and project name.
    ///
    /// - `/path/to/undertow/Undertow.xcworkspace` → root: `/path/to/undertow`, name: `Undertow`
    /// - `/path/to/undertow/Undertow.xcodeproj` → root: `/path/to/undertow`, name: `Undertow`
    /// - `/path/to/undertow` → root: `/path/to/undertow`, name: `undertow`
    static func resolveProject(path: String) -> (root: String, name: String) {
        let ext = (path as NSString).pathExtension
        if ext == "xcworkspace" || ext == "xcodeproj" {
            let root = (path as NSString).deletingLastPathComponent
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return (root, name)
        }
        return (path, (path as NSString).lastPathComponent)
    }
}
