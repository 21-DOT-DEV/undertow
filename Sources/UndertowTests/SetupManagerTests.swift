import Foundation
import Testing

@testable import UndertowKit

// MARK: - Config I/O Tests

@Suite("Config I/O")
struct ConfigIOTests {
    let tempHome: URL
    let manager: ConfigManager

    init() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndertowConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        manager = ConfigManager(home: tempHome)
    }

    @Test("reads nonexistent config as no projects")
    func readNonexistentConfig() {
        let projects = manager.readConfiguredProjects(from: manager.xcodeConfigPath)
        #expect(projects.isEmpty)
    }

    @Test("reads config with undertow entry")
    func readWithUndertow() throws {
        let json: [String: Any] = [
            "projects": [
                "/Users/test/myproject": [
                    "mcpServers": [
                        "undertow": [
                            "command": "/path/to/helper",
                            "args": ["--mcp"]
                        ]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(json, to: manager.xcodeConfigPath)

        let projects = manager.readConfiguredProjects(from: manager.xcodeConfigPath)
        #expect(projects == ["/Users/test/myproject"])
    }

    @Test("ignores projects without undertow entry")
    func ignoresNonUndertow() throws {
        let json: [String: Any] = [
            "projects": [
                "/Users/test/other": [
                    "mcpServers": [
                        "other-tool": ["command": "/path/to/other"]
                    ]
                ],
                "/Users/test/undertow-project": [
                    "mcpServers": [
                        "undertow": ["command": "/path/to/helper"]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(json, to: manager.xcodeConfigPath)

        let projects = manager.readConfiguredProjects(from: manager.xcodeConfigPath)
        #expect(projects.count == 1)
        #expect(projects.contains("/Users/test/undertow-project"))
    }

    @Test("writes undertow entry to new config")
    func writeNewConfig() throws {
        try manager.addProject(path: "/Users/test/myproject", target: .xcode)

        let json = manager.readConfigJSON(from: manager.xcodeConfigPath)
        let projects = json["projects"] as? [String: Any]
        let project = projects?["/Users/test/myproject"] as? [String: Any]
        let servers = project?["mcpServers"] as? [String: Any]
        let undertow = servers?["undertow"] as? [String: Any]

        #expect(undertow?["command"] as? String == manager.helperCommand)
        #expect(undertow?["args"] as? [String] == ["--mcp"])
    }

    @Test("preserves existing keys when adding project")
    func preservesExistingKeys() throws {
        let initial: [String: Any] = [
            "customSetting": true,
            "projects": [
                "/Users/test/existing": [
                    "mcpServers": [
                        "other-tool": ["command": "/other"]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(initial, to: manager.xcodeConfigPath)

        try manager.addProject(path: "/Users/test/new", target: .xcode)

        let json = manager.readConfigJSON(from: manager.xcodeConfigPath)
        #expect(json["customSetting"] as? Bool == true)

        let projects = json["projects"] as? [String: Any]
        #expect(projects?["/Users/test/existing"] != nil)
        #expect(projects?["/Users/test/new"] != nil)
    }

    @Test("removes undertow entry while preserving others")
    func removePreservesOthers() throws {
        let initial: [String: Any] = [
            "projects": [
                "/Users/test/project": [
                    "mcpServers": [
                        "undertow": ["command": "/helper"],
                        "other-tool": ["command": "/other"]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(initial, to: manager.xcodeConfigPath)

        try manager.removeProject(path: "/Users/test/project", target: .xcode)

        let json = manager.readConfigJSON(from: manager.xcodeConfigPath)
        let projects = json["projects"] as? [String: Any]
        let project = projects?["/Users/test/project"] as? [String: Any]
        let servers = project?["mcpServers"] as? [String: Any]

        #expect(servers?["undertow"] == nil)
        #expect(servers?["other-tool"] != nil)
    }

    @Test("writes to both Xcode and Claude Code targets")
    func writeBothTargets() throws {
        try manager.addProject(path: "/Users/test/project", target: .both)

        let xcodeProjects = manager.readConfiguredProjects(from: manager.xcodeConfigPath)
        let cliProjects = manager.readConfiguredProjects(from: manager.claudeCodeConfigPath)

        #expect(xcodeProjects == ["/Users/test/project"])
        #expect(cliProjects == ["/Users/test/project"])
    }

    @Test("removes from specific target only")
    func removeFromSpecificTarget() throws {
        try manager.addProject(path: "/Users/test/project", target: .both)
        try manager.removeProject(path: "/Users/test/project", target: .xcode)

        let xcodeProjects = manager.readConfiguredProjects(from: manager.xcodeConfigPath)
        let cliProjects = manager.readConfiguredProjects(from: manager.claudeCodeConfigPath)

        #expect(xcodeProjects.isEmpty)
        #expect(cliProjects == ["/Users/test/project"])
    }

    @Test("remove from nonexistent config is silent")
    func removeNonexistent() throws {
        try manager.removeProject(path: "/Users/test/nonexistent", target: .xcode)
    }
}

// MARK: - Setup Status Tests

@Suite("Setup Status")
struct SetupStatusTests {
    let tempHome: URL
    let manager: ConfigManager

    init() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndertowStatusTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        manager = ConfigManager(home: tempHome)
    }

    @Test("reports helper not installed when missing")
    func helperNotInstalled() {
        let status = manager.getSetupStatus()
        #expect(!status.helperInstalled)
        #expect(!status.symlinkValid)
    }

    @Test("reports helper installed when binary exists")
    func helperInstalled() throws {
        try FileManager.default.createDirectory(
            at: manager.installDir, withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: manager.helperPath.path,
            contents: "binary".data(using: .utf8)
        )

        let status = manager.getSetupStatus()
        #expect(status.helperInstalled)
    }

    @Test("reports symlink valid when pointing to existing binary")
    func symlinkValid() throws {
        let fm = FileManager.default

        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))

        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        let status = manager.getSetupStatus()
        #expect(status.helperInstalled)
        #expect(status.symlinkValid)
    }

    @Test("reports symlink invalid when target missing")
    func symlinkBroken() throws {
        let fm = FileManager.default

        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: "/nonexistent/path"
        )

        let status = manager.getSetupStatus()
        #expect(!status.symlinkValid)
    }

    @Test("includes configured projects from both config files")
    func configuredProjects() throws {
        try manager.addProject(path: "/Users/test/xcode-only", target: .xcode)
        try manager.addProject(path: "/Users/test/cli-only", target: .claudeCode)
        try manager.addProject(path: "/Users/test/both", target: .both)

        let status = manager.getSetupStatus()

        #expect(status.xcodeConfiguredProjects.contains("/Users/test/xcode-only"))
        #expect(status.xcodeConfiguredProjects.contains("/Users/test/both"))
        #expect(!status.xcodeConfiguredProjects.contains("/Users/test/cli-only"))

        #expect(status.claudeCodeConfiguredProjects.contains("/Users/test/cli-only"))
        #expect(status.claudeCodeConfiguredProjects.contains("/Users/test/both"))
        #expect(!status.claudeCodeConfiguredProjects.contains("/Users/test/xcode-only"))
    }
}

// MARK: - Project Verification Tests

@Suite("Project Verification")
struct ProjectVerificationTests {
    let tempHome: URL
    let manager: ConfigManager

    init() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndertowVerifyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        manager = ConfigManager(home: tempHome)
    }

    @Test("no config entry returns failed")
    func noConfigEntry() throws {
        // Setup helper + symlink but no config
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("No config entry"))
    }

    @Test("missing binary returns failed")
    func missingBinary() {
        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("Helper binary not found"))
    }

    @Test("valid config returns success")
    func validConfig() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        try manager.addProject(path: "/Users/test/project", target: .xcode)

        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(result.success)
        #expect(result.message == "OK")
    }

    @Test("broken symlink returns failed")
    func brokenSymlink() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: "/nonexistent/path"
        )

        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("Symlink"))
    }

    @Test("missing --mcp arg returns failed")
    func missingMcpArg() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        // Write config with no --mcp arg
        let json: [String: Any] = [
            "projects": [
                "/Users/test/project": [
                    "mcpServers": [
                        "undertow": [
                            "command": manager.helperCommand,
                            "args": ["--hook"]
                        ]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(json, to: manager.xcodeConfigPath)

        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("--mcp"))
    }

    @Test("mismatched PROJECT_DIR returns failed")
    func mismatchedProjectDir() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        let json: [String: Any] = [
            "projects": [
                "/Users/test/project": [
                    "mcpServers": [
                        "undertow": [
                            "command": manager.helperCommand,
                            "args": ["--mcp"],
                            "env": ["PROJECT_DIR": "/Users/test/wrong-project"]
                        ]
                    ]
                ]
            ]
        ]
        try manager.writeConfigJSON(json, to: manager.xcodeConfigPath)

        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("PROJECT_DIR"))
    }

    @Test("finds entry in Claude Code config when not in Xcode config")
    func findsClaudeCodeEntry() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: manager.installDir, withIntermediateDirectories: true)
        fm.createFile(atPath: manager.helperPath.path, contents: "binary".data(using: .utf8))
        try fm.createDirectory(at: manager.symlinkDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: manager.symlinkPath.path,
            withDestinationPath: manager.helperPath.path
        )

        // Only write to Claude Code config, not Xcode
        try manager.addProject(path: "/Users/test/project", target: .claudeCode)

        // Xcode verify should fail (no xcode entry)
        let result = manager.verifyProject(path: "/Users/test/project")
        #expect(!result.success)
        #expect(result.message.contains("No config entry"))
    }
}

// MARK: - Bookmark State Tests

@Suite("Bookmark State")
struct BookmarkStateTests {

    @Test("initial state is noBookmark")
    func initialState() {
        let defaults = UserDefaults(suiteName: "test.undertow.bookmark.\(UUID().uuidString)")!
        let bookmark = BookmarkManager(defaults: defaults)
        #expect(bookmark.accessState == .noBookmark)
    }

    @Test("restoreBookmark with no stored data stays noBookmark")
    func restoreEmpty() {
        let defaults = UserDefaults(suiteName: "test.undertow.bookmark.\(UUID().uuidString)")!
        let bookmark = BookmarkManager(defaults: defaults)
        bookmark.restoreBookmark()
        #expect(bookmark.accessState == .noBookmark)
    }

    @Test("restoreBookmark with invalid data goes to bookmarkStale")
    func restoreInvalid() {
        let suiteName = "test.undertow.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: BookmarkManager.bookmarkKey)

        let bookmark = BookmarkManager(defaults: defaults)
        bookmark.restoreBookmark()
        #expect(bookmark.accessState == .bookmarkStale)
    }

    @Test("revokeAccess resets to noBookmark and clears defaults")
    func revokeAccess() {
        let suiteName = "test.undertow.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data([0x00]), forKey: BookmarkManager.bookmarkKey)

        let bookmark = BookmarkManager(defaults: defaults)
        bookmark.revokeAccess()

        #expect(bookmark.accessState == .noBookmark)
        #expect(defaults.data(forKey: BookmarkManager.bookmarkKey) == nil)
    }

    @Test("full grant → revoke cycle")
    func grantRevokeCycle() throws {
        let suiteName = "test.undertow.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let bookmark = BookmarkManager(defaults: defaults)

        // Create a real temp directory for bookmark
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndertowBookmarkTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Grant access
        try bookmark.storeAndAccess(url: tempDir)
        #expect(bookmark.accessState == .accessGranted)
        #expect(defaults.data(forKey: BookmarkManager.bookmarkKey) != nil)

        // Revoke
        bookmark.revokeAccess()
        #expect(bookmark.accessState == .noBookmark)
        #expect(defaults.data(forKey: BookmarkManager.bookmarkKey) == nil)
    }

    @Test("restore succeeds after store")
    func restoreAfterStore() throws {
        let suiteName = "test.undertow.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UndertowBookmarkTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Store bookmark
        let bookmark1 = BookmarkManager(defaults: defaults)
        try bookmark1.storeAndAccess(url: tempDir)
        #expect(bookmark1.accessState == .accessGranted)

        // New instance restores from defaults
        let bookmark2 = BookmarkManager(defaults: defaults)
        bookmark2.restoreBookmark()
        #expect(bookmark2.accessState == .accessGranted)
    }
}
