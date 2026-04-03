import Foundation

/// Target configuration file for MCP server setup.
public enum ConfigTarget: String, Codable, Sendable {
    /// Xcode Coding Assistant config at ~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json
    case xcode
    /// Claude Code CLI config at ~/.claude.json
    case claudeCode = "claude-code"
    /// Both config files
    case both
}

/// Represents a project configured with Undertow's MCP server.
public struct ProjectConfig: Codable, Sendable, Identifiable, Hashable {
    public var id: String { path }

    /// Absolute path to the project directory.
    public var path: String

    /// Display name derived from the path.
    public var displayName: String {
        (path as NSString).lastPathComponent
    }

    /// Whether this project is configured in Xcode's Coding Assistant config.
    public var xcodeConfigured: Bool

    /// Whether this project is configured in Claude Code CLI config.
    public var claudeCodeConfigured: Bool

    /// Last time the MCP server was verified working for this project.
    public var lastVerified: Date?

    public init(
        path: String,
        xcodeConfigured: Bool = false,
        claudeCodeConfigured: Bool = false,
        lastVerified: Date? = nil
    ) {
        self.path = path
        self.xcodeConfigured = xcodeConfigured
        self.claudeCodeConfigured = claudeCodeConfigured
        self.lastVerified = lastVerified
    }
}

/// Aggregated setup status returned by the Bridge.
public struct SetupStatusReport: Codable, Sendable {
    /// Whether UndertowHelper binary exists at the expected install path.
    public var helperInstalled: Bool

    /// Whether the symlink at ~/.undertow/bin/UndertowHelper is valid.
    public var symlinkValid: Bool

    /// Absolute path to the installed helper binary.
    public var helperPath: String?

    /// Absolute path to the symlink.
    public var symlinkPath: String?

    /// Project paths currently configured in Xcode's Coding Assistant config.
    public var xcodeConfiguredProjects: [String]

    /// Project paths currently configured in Claude Code CLI config.
    public var claudeCodeConfiguredProjects: [String]

    public init(
        helperInstalled: Bool = false,
        symlinkValid: Bool = false,
        helperPath: String? = nil,
        symlinkPath: String? = nil,
        xcodeConfiguredProjects: [String] = [],
        claudeCodeConfiguredProjects: [String] = []
    ) {
        self.helperInstalled = helperInstalled
        self.symlinkValid = symlinkValid
        self.helperPath = helperPath
        self.symlinkPath = symlinkPath
        self.xcodeConfiguredProjects = xcodeConfiguredProjects
        self.claudeCodeConfiguredProjects = claudeCodeConfiguredProjects
    }
}

/// Result of verifying an MCP server for a project.
public struct VerificationResult: Codable, Sendable {
    public var success: Bool
    public var message: String
    public var responseTime: TimeInterval?

    public init(success: Bool, message: String, responseTime: TimeInterval? = nil) {
        self.success = success
        self.message = message
        self.responseTime = responseTime
    }
}
