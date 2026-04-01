import Foundation
import Subprocess
import UndertowKit

/// Observes Xcode build results by watching DerivedData for `.xcactivitylog` files.
///
/// Detects new build logs and parses them to extract success/failure status,
/// error count, warning count, and error messages.
actor BuildLogObserver {
    private var eventSource: DispatchSourceFileSystemObject?
    private var lastKnownLog: URL?
    private var continuation: AsyncStream<BuildStatus>.Continuation?

    /// The current build status.
    private(set) var latestStatus: BuildStatus?

    /// Stream of build status updates.
    let buildStatuses: AsyncStream<BuildStatus>

    init() {
        var captured: AsyncStream<BuildStatus>.Continuation?
        self.buildStatuses = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    /// Start watching for build logs in DerivedData.
    ///
    /// - Parameter projectName: The Xcode project name to locate its DerivedData folder.
    func start(projectName: String) {
        let derivedDataPath = findDerivedDataBuildLogsPath(projectName: projectName)
        guard let logsPath = derivedDataPath else {
            fputs("BuildLogObserver: could not find DerivedData build logs for \(projectName)\n", stderr)
            // Fall back to polling
            startPolling(projectName: projectName)
            return
        }

        watchDirectory(at: logsPath)
        fputs("BuildLogObserver: watching \(logsPath.path)\n", stderr)
    }

    /// Stop watching.
    func stop() {
        eventSource?.cancel()
        eventSource = nil
        continuation?.finish()
    }

    // MARK: - Directory Watching

    private func watchDirectory(at url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            fputs("BuildLogObserver: failed to open \(url.path)\n", stderr)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.checkForNewLogs(in: url) }
        }

        source.setCancelHandler {
            close(fd)
        }

        eventSource = source
        source.resume()

        // Check immediately for existing logs
        Task { await checkForNewLogs(in: url) }
    }

    private func startPolling(projectName: String) {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if let logsPath = findDerivedDataBuildLogsPath(projectName: projectName) {
                    // Found it — switch to watching
                    watchDirectory(at: logsPath)
                    fputs("BuildLogObserver: found build logs, now watching \(logsPath.path)\n", stderr)
                    return
                }
            }
        }
    }

    // MARK: - Log Discovery

    private func checkForNewLogs(in directory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let logs = contents
            .filter { url in
                url.pathExtension == "xcactivitylog"
                    && (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 0
            }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return aDate > bDate
            }

        guard let newest = logs.first, newest != lastKnownLog else { return }
        lastKnownLog = newest
        parseActivityLog(at: newest)
    }

    // MARK: - Log Parsing

    /// Parse an `.xcactivitylog` file (gzip-compressed SLF format).
    private func parseActivityLog(at url: URL) {
        Task {
            guard let logString = await decompressLog(at: url) else {
                fputs("BuildLogObserver: failed to decompress \(url.lastPathComponent)\n", stderr)
                return
            }

            let status = extractBuildStatus(from: logString)
            latestStatus = status
            continuation?.yield(status)
        }
    }

    /// Decompress an xcactivitylog using gunzip via Subprocess.
    private func decompressLog(at url: URL) async -> String? {
        do {
            let result = try await Subprocess.run(
                .name("gunzip"),
                arguments: .init(["-c", url.path]),
                output: .string(limit: 10 * 1024 * 1024), // 10MB limit
                error: .string(limit: 4096)
            )
            guard case .exited(0) = result.terminationStatus else { return nil }
            return result.standardOutput
        } catch {
            return nil
        }
    }

    /// Extract build status from the decompressed log content.
    private func extractBuildStatus(from log: String) -> BuildStatus {
        // Look for build result indicators in the SLF format
        let lines = log.components(separatedBy: "\n")
        var errors: [String] = []
        var warningCount = 0
        var succeeded = true

        for line in lines {
            if line.contains("error:") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    errors.append(String(trimmed.prefix(200)))
                }
            }
            if line.contains("warning:") {
                warningCount += 1
            }
            if line.contains("BUILD FAILED") || line.contains("build stopped") {
                succeeded = false
            }
        }

        // Cap errors to avoid bloating context
        let cappedErrors = Array(errors.prefix(10))

        return BuildStatus(
            succeeded: succeeded && errors.isEmpty,
            errorCount: errors.count,
            warningCount: warningCount,
            errors: cappedErrors
        )
    }

    // MARK: - DerivedData Path Discovery

    private func findDerivedDataBuildLogsPath(projectName: String) -> URL? {
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        // Find the directory matching our project name (format: ProjectName-hashstring)
        let projectDir = contents.first { url in
            url.lastPathComponent.hasPrefix(projectName + "-")
        }

        guard let projectDir else { return nil }

        let logsDir = projectDir
            .appendingPathComponent("Logs")
            .appendingPathComponent("Build")

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: logsDir.path, isDirectory: &isDir), isDir.boolValue {
            return logsDir
        }

        return nil
    }


}
