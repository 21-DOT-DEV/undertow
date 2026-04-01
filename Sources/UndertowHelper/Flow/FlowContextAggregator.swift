import Foundation
import UndertowKit

/// Combines all observer streams into a unified `FlowContext`.
///
/// The aggregator owns the three observers (file system, build log, Xcode state)
/// and merges their outputs into a single, up-to-date `FlowContext` snapshot
/// that can be read synchronously by hook handlers and MCP tools.
actor FlowContextAggregator {
    private let fileObserver: FileSystemObserver
    private let buildObserver: BuildLogObserver
    private let xcodeObserver: XcodeObserver

    private var fileTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    private var xcodeTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var dirty = false

    /// The latest aggregated flow context.
    private(set) var currentContext = FlowContext()

    init() {
        self.fileObserver = FileSystemObserver(path: "")
        self.buildObserver = BuildLogObserver()
        self.xcodeObserver = XcodeObserver()
    }

    /// Start all observers.
    ///
    /// - Parameter projectPath: Path to the project workspace, project file, or root directory.
    func start(projectPath: String) async {
        // Resolve workspace/project path into a root directory and project name
        let (projectRoot, projectName) = Self.resolveProject(path: projectPath)

        let fsObserver = FileSystemObserver(path: projectRoot)
        await fsObserver.start()

        await buildObserver.start(projectName: projectName)
        await xcodeObserver.start()

        // Subscribe to file events
        fileTask = Task { [weak self] in
            for await event in fsObserver.fileEvents {
                guard !Task.isCancelled else { return }
                await self?.handleFileEvent(event)
            }
        }

        // Subscribe to build status updates
        buildTask = Task { [weak self] in
            for await status in self?.buildObserver.buildStatuses ?? emptyStream() {
                guard !Task.isCancelled else { return }
                await self?.handleBuildStatus(status)
            }
        }

        // Subscribe to Xcode state updates
        xcodeTask = Task { [weak self] in
            for await state in self?.xcodeObserver.stateUpdates ?? emptyStream() {
                guard !Task.isCancelled else { return }
                await self?.handleXcodeState(state)
            }
        }

        // Periodically persist context to disk for hook handlers
        persistTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if await self.dirty {
                    await self.persistToDisk()
                }
            }
        }

        fputs("FlowContextAggregator: started for \(projectRoot) (project: \(projectName))\n", stderr)
    }

    /// Stop all observers and tasks.
    func stop() async {
        fileTask?.cancel()
        buildTask?.cancel()
        xcodeTask?.cancel()
        persistTask?.cancel()
        await fileObserver.stop()
        await buildObserver.stop()
        await xcodeObserver.stop()
        persistToDisk()
    }

    /// Get the current flow context as encoded JSON data.
    func contextData() throws -> Data {
        currentContext.timestamp = .now
        return try JSONEncoder().encode(currentContext)
    }

    /// Format the current context as a concise, human-readable summary for injection.
    func contextSummary() -> String {
        let ctx = currentContext

        var parts: [String] = []

        if let file = ctx.activeFile {
            let fileName = (file as NSString).lastPathComponent
            var fileInfo = "Active file: \(fileName)"
            if let line = ctx.cursorLine {
                fileInfo += " (line \(line))"
            }
            parts.append(fileInfo)
        }

        if let build = ctx.buildStatus {
            if build.succeeded {
                parts.append("Last build: succeeded")
            } else {
                var buildInfo = "Last build: FAILED (\(build.errorCount) error\(build.errorCount == 1 ? "" : "s")"
                if build.warningCount > 0 {
                    buildInfo += ", \(build.warningCount) warning\(build.warningCount == 1 ? "" : "s")"
                }
                buildInfo += ")"
                if !build.errors.isEmpty {
                    let errorList = build.errors.prefix(3).map { "  - \($0)" }.joined(separator: "\n")
                    buildInfo += "\n\(errorList)"
                }
                parts.append(buildInfo)
            }
        }

        if !ctx.recentEdits.isEmpty {
            let editPaths = ctx.recentEdits.prefix(5).map {
                ($0.path as NSString).lastPathComponent
            }
            let unique = Array(dict: editPaths)
            parts.append("Recent edits: \(unique.joined(separator: ", "))")
        }

        if !ctx.recentNavigation.isEmpty {
            let navPaths = ctx.recentNavigation.prefix(5).map {
                ($0 as NSString).lastPathComponent
            }
            let unique = Array(dict: navPaths)
            parts.append("Recently visited: \(unique.joined(separator: ", "))")
        }

        if let scheme = ctx.activeScheme {
            var schemeInfo = "Scheme: \(scheme)"
            if let dest = ctx.activeDestination {
                schemeInfo += " → \(dest)"
            }
            parts.append(schemeInfo)
        }

        if let workspace = ctx.workspaceURL {
            let workspaceName = (workspace as NSString).lastPathComponent
            parts.append("Workspace: \(workspaceName)")
        }

        if parts.isEmpty {
            return "[Undertow] Flow context: no active Xcode session detected."
        }

        return "[Undertow Flow Context]\n" + parts.joined(separator: "\n")
    }

    // MARK: - Event Handlers

    private func persistToDisk() {
        do {
            currentContext.timestamp = .now
            let data = try JSONEncoder().encode(currentContext)
            try data.write(to: UndertowXPC.flowContextFile, options: .atomic)
            dirty = false
        } catch {
            fputs("FlowContextAggregator: failed to persist context: \(error)\n", stderr)
        }
    }

    private func handleFileEvent(_ event: FileEvent) {
        currentContext.recentEdits.insert(event, at: 0)
        // Keep only the last 20 edits
        if currentContext.recentEdits.count > 20 {
            currentContext.recentEdits = Array(currentContext.recentEdits.prefix(20))
        }
        dirty = true
    }

    private func handleBuildStatus(_ status: BuildStatus) {
        currentContext.buildStatus = status
        dirty = true
    }

    private func handleXcodeState(_ state: XcodeObserver.XcodeState) {
        currentContext.activeFile = state.activeFile
        currentContext.cursorLine = state.cursorLine
        currentContext.workspaceURL = state.workspaceURL
        currentContext.activeScheme = state.activeScheme
        currentContext.activeDestination = state.activeDestination

        // Merge navigation from Xcode observer
        for path in state.recentNavigation {
            if !currentContext.recentNavigation.contains(path) {
                currentContext.recentNavigation.append(path)
            }
        }
        if currentContext.recentNavigation.count > 20 {
            currentContext.recentNavigation = Array(currentContext.recentNavigation.prefix(20))
        }
        dirty = true
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

// MARK: - Helpers

/// Create an empty async stream (used as a fallback when self is nil).
private func emptyStream<T>() -> AsyncStream<T> {
    AsyncStream { $0.finish() }
}

private extension Array where Element: Hashable {
    /// Deduplicate while preserving order.
    init(dict elements: [Element]) {
        var seen = Set<Element>()
        self = elements.filter { seen.insert($0).inserted }
    }
}
