import Foundation

/// Manages Undertow configuration file I/O and installation path checking.
///
/// All filesystem operations are relative to `home`, which defaults to the
/// real home directory (not the sandbox container) but can be overridden for testing.
public final class ConfigManager {
    public let home: URL
    private let fileManager: FileManager

    /// The real home directory, bypassing the sandbox container path.
    ///
    /// In a sandboxed app, `FileManager.default.homeDirectoryForCurrentUser` returns
    /// the container path (`~/Library/Containers/<bundle-id>/Data/`). This uses
    /// `getpwuid` to get the actual `/Users/<name>/` path instead.
    public static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public init(
        home: URL = ConfigManager.realHomeDirectory,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.fileManager = fileManager
    }

    // MARK: - Paths

    public var installDir: URL {
        home.appendingPathComponent("Library/Application Support/Undertow/bin")
    }

    public var helperPath: URL {
        installDir.appendingPathComponent("UndertowHelper")
    }

    public var symlinkDir: URL {
        home.appendingPathComponent(".undertow/bin")
    }

    public var symlinkPath: URL {
        symlinkDir.appendingPathComponent("UndertowHelper")
    }

    public var xcodeConfigPath: URL {
        home.appendingPathComponent(
            "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/.claude.json"
        )
    }

    public var claudeCodeConfigPath: URL {
        home.appendingPathComponent(".claude.json")
    }

    /// The command path used in MCP server config entries (symlink, avoids spaces).
    public var helperCommand: String {
        symlinkPath.path
    }

    // MARK: - Setup Status

    public func getSetupStatus() -> SetupStatusReport {
        let helperExists = fileManager.fileExists(atPath: helperPath.path)

        var symlinkOK = false
        if let dest = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path) {
            symlinkOK = fileManager.fileExists(atPath: dest)
        }

        let xcodeProjects = readConfiguredProjects(from: xcodeConfigPath)
        let claudeCodeProjects = readConfiguredProjects(from: claudeCodeConfigPath)

        return SetupStatusReport(
            helperInstalled: helperExists,
            symlinkValid: symlinkOK,
            helperPath: helperPath.path,
            symlinkPath: symlinkPath.path,
            xcodeConfiguredProjects: xcodeProjects,
            claudeCodeConfiguredProjects: claudeCodeProjects
        )
    }

    // MARK: - Project Config

    public func addProject(path: String, target: ConfigTarget) throws {
        let entry: [String: Any] = [
            "command": helperCommand,
            "args": ["--mcp"],
            "env": ["PROJECT_DIR": path]
        ]

        if target == .xcode || target == .both {
            try writeUndertowEntry(entry, forProject: path, inConfigAt: xcodeConfigPath)
        }
        if target == .claudeCode || target == .both {
            try writeUndertowEntry(entry, forProject: path, inConfigAt: claudeCodeConfigPath)
        }
    }

    public func removeProject(path: String, target: ConfigTarget) throws {
        if target == .xcode || target == .both {
            try removeUndertowEntry(forProject: path, inConfigAt: xcodeConfigPath)
        }
        if target == .claudeCode || target == .both {
            try removeUndertowEntry(forProject: path, inConfigAt: claudeCodeConfigPath)
        }
    }

    // MARK: - JSON Config I/O

    public func readConfiguredProjects(from configPath: URL) -> [String] {
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: Any]
        else { return [] }

        return projects.compactMap { path, value in
            guard let projectDict = value as? [String: Any],
                  let servers = projectDict["mcpServers"] as? [String: Any],
                  servers["undertow"] != nil
            else { return nil }
            return path
        }
    }

    public func writeUndertowEntry(
        _ entry: [String: Any],
        forProject projectPath: String,
        inConfigAt configPath: URL
    ) throws {
        var json = readConfigJSON(from: configPath)

        var projects = json["projects"] as? [String: Any] ?? [:]
        var projectDict = projects[projectPath] as? [String: Any] ?? [:]
        var servers = projectDict["mcpServers"] as? [String: Any] ?? [:]

        servers["undertow"] = entry
        projectDict["mcpServers"] = servers
        projects[projectPath] = projectDict
        json["projects"] = projects

        try writeConfigJSON(json, to: configPath)
    }

    public func removeUndertowEntry(
        forProject projectPath: String,
        inConfigAt configPath: URL
    ) throws {
        var json = readConfigJSON(from: configPath)

        guard var projects = json["projects"] as? [String: Any],
              var projectDict = projects[projectPath] as? [String: Any],
              var servers = projectDict["mcpServers"] as? [String: Any]
        else { return }

        servers.removeValue(forKey: "undertow")
        projectDict["mcpServers"] = servers
        projects[projectPath] = projectDict
        json["projects"] = projects

        try writeConfigJSON(json, to: configPath)
    }

    // MARK: - Project Verification

    public func verifyProject(path projectPath: String) -> VerificationResult {
        // Check helper binary exists
        guard fileManager.fileExists(atPath: helperPath.path) else {
            return VerificationResult(success: false, message: "Helper binary not found")
        }

        // Check symlink is valid
        guard let dest = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path),
              fileManager.fileExists(atPath: dest)
        else {
            return VerificationResult(success: false, message: "Symlink is missing or broken")
        }

        // Check Xcode config entry
        let json = readConfigJSON(from: xcodeConfigPath)
        guard let projects = json["projects"] as? [String: Any],
              let projectDict = projects[projectPath] as? [String: Any],
              let servers = projectDict["mcpServers"] as? [String: Any],
              let undertow = servers["undertow"] as? [String: Any]
        else {
            return VerificationResult(success: false, message: "No config entry for this project")
        }

        // Check command points to our helper
        if let command = undertow["command"] as? String, command != helperCommand {
            return VerificationResult(success: false, message: "Config command path mismatch")
        }

        // Check --mcp arg
        if let args = undertow["args"] as? [String], !args.contains("--mcp") {
            return VerificationResult(success: false, message: "Missing --mcp argument in config")
        }

        // Check PROJECT_DIR matches
        if let env = undertow["env"] as? [String: String], env["PROJECT_DIR"] != projectPath {
            return VerificationResult(
                success: false, message: "PROJECT_DIR mismatch in config"
            )
        }

        return VerificationResult(success: true, message: "OK")
    }

    public func readConfigJSON(from path: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    public func writeConfigJSON(_ json: [String: Any], to path: URL) throws {
        let dir = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: path, options: .atomic)
    }
}
