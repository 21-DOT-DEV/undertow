import Foundation
import Testing

@Suite("UndertowHelper Integration", .serialized)
struct HelperIntegrationTests {

    // MARK: - Hook Mode

    @Suite("Hook mode")
    struct HookTests {
        let harness = TestHarness()

        @Test("hook outputs flow context to stdout")
        func hookOutputsFlowContext() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.exitCode == 0)
            #expect(result.stdout.contains("[Undertow Flow Context]"))
        }

        @Test("hook includes git branch")
        func hookIncludesGitBranch() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try await fixture.runGit(["checkout", "-b", "feature/test-branch"])

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Branch: feature/test-branch"))
        }

        @Test("hook includes uncommitted changes")
        func hookIncludesUncommittedChanges() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/App.swift", content: "import Foundation\n")

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Uncommitted changes"))
            #expect(result.stdout.contains("App.swift"))
        }

        @Test("hook includes recent commits")
        func hookIncludesRecentCommits() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("hello.swift", content: "print(\"hello\")\n")
            try await fixture.runGit(["add", "."])
            try await fixture.runGit(["commit", "-m", "Add hello"])

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Recent commits"))
            #expect(result.stdout.contains("Add hello"))
            #expect(result.stdout.contains("Initial commit"))
        }

        @Test("hook includes staged diff")
        func hookIncludesStagedDiff() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Staged.swift", content: "let x = 1\n")
            try await fixture.runGit(["add", "Staged.swift"])

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("Staged for commit"))
            #expect(result.stdout.contains("Staged.swift"))
        }

        @Test("hook handles clean repo")
        func hookHandlesCleanRepo() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            let result = try await harness.runWithStdin(
                arguments: ["--hook", "user-prompt-submit"],
                stdin: "{}",
                environment: ["PROJECT_DIR": fixture.path]
            )

            #expect(result.succeeded)
            #expect(result.stdout.contains("[Undertow Flow Context]"))
            #expect(result.stdout.contains("Recent commits"))
        }

        @Test("hook handles unknown event")
        func hookHandlesUnknownEvent() async throws {
            let result = try await harness.runWithStdin(
                arguments: ["--hook", "unknown-event"],
                stdin: "{}"
            )

            #expect(result.exitCode == 0)
            #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
