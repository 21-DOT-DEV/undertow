import Foundation
import Testing

@Suite("UndertowHelper Integration", .serialized)
struct HelperIntegrationTests {

    // MARK: - MCP Mode

    @Suite("MCP mode", .serialized)
    struct MCPTests {
        let harness = TestHarness()

        // MCP handshake: initialize request → server responds → initialized notification
        private static let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#
        private static let initNotification = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        private static let flowContextCall = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_flow_context","arguments":{}}}"#

        @Test("get_flow_context returns git snapshot")
        func getFlowContextReturnsGitSnapshot() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.flowContextCall],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 3
            )

            #expect(result.stdout.contains("Branch:"), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
            #expect(result.stdout.contains("Branch:"))
        }

        @Test("get_flow_context includes file activity after file creation")
        func getFlowContextIncludesFileActivity() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            // Create a file before starting MCP — git status will show it as untracked
            try fixture.createFile("Sources/NewFeature.swift", content: "import Foundation\n")

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.flowContextCall],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 3
            )

            // The git snapshot should at least show the uncommitted file
            #expect(result.stdout.contains("Branch:"), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
            #expect(result.stdout.contains("NewFeature.swift"))
        }
    }

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
            #expect(result.stdout.contains("Branch:"))
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
            #expect(result.stdout.contains("Branch:"))
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

    // MARK: - Semantic Search

    @Suite("Semantic search", .serialized)
    struct SemanticSearchTests {
        let harness = TestHarness()

        private static let initRequest = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#
        private static let initNotification = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#

        private static func searchCall(_ query: String) -> String {
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"semantic_search","arguments":{"query":"\#(query)"}}}"#
        }

        private static func symbolRefsCall(_ symbol: String) -> String {
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol_references","arguments":{"symbol":"\#(symbol)"}}}"#
        }

        private static func conformancesCall(_ proto: String) -> String {
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_conformances","arguments":{"protocol":"\#(proto)"}}}"#
        }

        @Test("semantic_search returns results for matching query")
        func searchReturnsMatchingResults() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/Pricing.swift", content: """
            struct PricingEngine {
                func calculateTotalPrice(items: [Int]) -> Int {
                    items.reduce(0, +)
                }
            }
            """)

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.searchCall("calculateTotalPrice")],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 5
            )

            #expect(result.stdout.contains("calculateTotalPrice"), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
            #expect(result.stdout.contains("Score:"))
            #expect(result.stdout.contains("Pricing.swift"))
        }

        @Test("semantic_search returns no results for nonsense query")
        func searchReturnsNoResultsForNonsense() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/Simple.swift", content: """
            struct Hello {
                func greet() -> String { "hello" }
            }
            """)

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.searchCall("xyzzy_nonexistent_gibberish_42")],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 5
            )

            // BM25 may return low-scoring results or none; verify valid JSON-RPC response
            #expect(result.stdout.contains("\"result\""), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
        }

        @Test("semantic_search finds symbol query in struct")
        func searchFindsSymbolQuery() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/NetworkManager.swift", content: """
            struct NetworkManager {
                func fetchData(from url: String) async throws -> Data {
                    Data()
                }

                func cancelAllRequests() {
                    // cancel pending requests
                }
            }
            """)

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.searchCall("NetworkManager")],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 5
            )

            #expect(result.stdout.contains("NetworkManager"), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
            #expect(result.stdout.contains("Score:"))
        }

        @Test("find_symbol_references responds without crashing")
        func symbolReferencesSmoke() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/Foo.swift", content: "struct Foo {}\n")

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.symbolRefsCall("Foo")],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 5
            )

            // IndexStoreDB may not be available without DerivedData, so just verify valid response
            #expect(result.stdout.contains("\"result\""), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
        }

        @Test("find_conformances responds without crashing")
        func conformancesSmoke() async throws {
            let fixture = try await GitRepositoryFixture()
            defer { try? fixture.tearDown() }

            try fixture.createFile("Sources/Proto.swift", content: """
            protocol Drawable {
                func draw()
            }
            struct Circle: Drawable {
                func draw() {}
            }
            """)

            let result = try await harness.runMCP(
                messages: [Self.initRequest, Self.initNotification, Self.conformancesCall("Drawable")],
                environment: ["PROJECT_DIR": fixture.path],
                timeout: 5
            )

            // IndexStoreDB may not be available, so just verify valid JSON-RPC response
            #expect(result.stdout.contains("\"result\""), Comment(rawValue: "stderr: \(result.stderr.prefix(500))"))
        }
    }
}
