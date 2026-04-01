import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Result of running UndertowHelper.
struct CommandResult {
    let exitCode: Int
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Harness for running UndertowHelper as a subprocess in tests.
struct TestHarness {
    /// Path to the built UndertowHelper binary.
    let executablePath: FilePath

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.executablePath = FilePath("\(home)/Library/Application Support/Undertow/bin/UndertowHelper")
    }

    /// Run UndertowHelper with the given arguments and optional environment overrides.
    func run(
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil
    ) async throws -> CommandResult {
        let result = try await Subprocess.run(
            .path(executablePath),
            arguments: .init(arguments),
            workingDirectory: workingDirectory.map { FilePath($0) },
            output: .string(limit: 256 * 1024),
            error: .string(limit: 64 * 1024)
        )

        let exitCode: Int
        if case .exited(let code) = result.terminationStatus {
            exitCode = Int(code)
        } else {
            exitCode = -1
        }

        return CommandResult(
            exitCode: exitCode,
            stdout: result.standardOutput ?? "",
            stderr: result.standardError ?? ""
        )
    }

    /// Run UndertowHelper with stdin data piped via shell.
    /// Used for hook testing where the hook reads stdin.
    func runWithStdin(
        arguments: [String],
        stdin: String,
        environment: [String: String] = [:]
    ) async throws -> CommandResult {
        // Build a shell command that exports env vars and pipes stdin
        let escapedPath = executablePath.string.replacingOccurrences(of: "'", with: "'\\''")
        let args = arguments.map { $0.replacingOccurrences(of: "'", with: "'\\''") }
        let argString = args.map { "'\($0)'" }.joined(separator: " ")

        var exports = ""
        for (key, value) in environment {
            let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
            exports += "export \(key)='\(escapedValue)'; "
        }
        let shellCommand = "\(exports)echo '{}' | '\(escapedPath)' \(argString)"

        let result = try await Subprocess.run(
            .path("/bin/sh"),
            arguments: ["-c", shellCommand],
            output: .string(limit: 256 * 1024),
            error: .string(limit: 64 * 1024)
        )

        let exitCode: Int
        if case .exited(let code) = result.terminationStatus {
            exitCode = Int(code)
        } else {
            exitCode = -1
        }

        return CommandResult(
            exitCode: exitCode,
            stdout: result.standardOutput ?? "",
            stderr: result.standardError ?? ""
        )
    }
}

/// Creates an isolated temporary git repository for testing.
struct GitRepositoryFixture {
    let path: String
    private let url: URL

    init() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("undertow-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.url = tempDir
        self.path = tempDir.path

        try await runGit(["init"])
        try await runGit(["config", "user.name", "Test User"])
        try await runGit(["config", "user.email", "test@example.com"])

        let readme = tempDir.appendingPathComponent("README.md")
        try "# Test Project\n".write(to: readme, atomically: true, encoding: .utf8)
        try await runGit(["add", "."])
        try await runGit(["commit", "-m", "Initial commit"])
    }

    @discardableResult
    func runGit(_ arguments: [String]) async throws -> String {
        let result = try await Subprocess.run(
            .name("git"),
            arguments: .init(arguments),
            workingDirectory: FilePath(path),
            output: .string(limit: 65536),
            error: .string(limit: 65536)
        )
        guard case .exited(0) = result.terminationStatus else {
            throw FixtureError.gitFailed(
                arguments.joined(separator: " "),
                result.standardError ?? "unknown error"
            )
        }
        return result.standardOutput ?? ""
    }

    func createFile(_ name: String, content: String) throws {
        let fileURL = url.appendingPathComponent(name)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func tearDown() throws {
        try FileManager.default.removeItem(at: url)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case gitFailed(String, String)
        var description: String {
            switch self {
            case .gitFailed(let cmd, let err): "git \(cmd) failed: \(err)"
            }
        }
    }
}
