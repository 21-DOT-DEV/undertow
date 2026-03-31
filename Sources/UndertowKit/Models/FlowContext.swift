import Foundation

/// Aggregated snapshot of the developer's current activity.
///
/// Combines file system events, build status, and Xcode state
/// into a single context object injected into every agent prompt.
public struct FlowContext: Codable, Sendable {
    /// The file currently being edited.
    public var activeFile: String?

    /// Cursor line in the active file.
    public var cursorLine: Int?

    /// Files edited recently, ordered by most recent first.
    public var recentEdits: [FileEvent]

    /// Files navigated to recently.
    public var recentNavigation: [String]

    /// Current build status.
    public var buildStatus: BuildStatus?

    /// Active Xcode scheme name.
    public var activeScheme: String?

    /// Active simulator or destination.
    public var activeDestination: String?

    /// Workspace URL.
    public var workspaceURL: String?

    /// Timestamp of this snapshot.
    public var timestamp: Date

    public init(
        activeFile: String? = nil,
        cursorLine: Int? = nil,
        recentEdits: [FileEvent] = [],
        recentNavigation: [String] = [],
        buildStatus: BuildStatus? = nil,
        activeScheme: String? = nil,
        activeDestination: String? = nil,
        workspaceURL: String? = nil,
        timestamp: Date = .now
    ) {
        self.activeFile = activeFile
        self.cursorLine = cursorLine
        self.recentEdits = recentEdits
        self.recentNavigation = recentNavigation
        self.buildStatus = buildStatus
        self.activeScheme = activeScheme
        self.activeDestination = activeDestination
        self.workspaceURL = workspaceURL
        self.timestamp = timestamp
    }
}

/// A file system event observed by the flow engine.
public struct FileEvent: Codable, Sendable {
    public enum EventType: String, Codable, Sendable {
        case created, modified, deleted, renamed
    }

    public var path: String
    public var type: EventType
    public var timestamp: Date

    public init(path: String, type: EventType, timestamp: Date = .now) {
        self.path = path
        self.type = type
        self.timestamp = timestamp
    }
}

/// Summary of the most recent build result.
public struct BuildStatus: Codable, Sendable {
    public var succeeded: Bool
    public var errorCount: Int
    public var warningCount: Int
    public var errors: [String]
    public var timestamp: Date

    public init(
        succeeded: Bool,
        errorCount: Int = 0,
        warningCount: Int = 0,
        errors: [String] = [],
        timestamp: Date = .now
    ) {
        self.succeeded = succeeded
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.errors = errors
        self.timestamp = timestamp
    }
}
