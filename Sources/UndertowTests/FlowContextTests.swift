import Foundation
import Testing
@testable import UndertowKit

@Suite("FlowContext")
struct FlowContextTests {

    // MARK: - Serialization

    @Suite("Codable round-trip")
    struct Serialization {
        @Test("encodes and decodes empty context")
        func emptyContext() throws {
            let context = FlowContext()
            let data = try JSONEncoder().encode(context)
            let decoded = try JSONDecoder().decode(FlowContext.self, from: data)

            #expect(decoded.activeFile == nil)
            #expect(decoded.cursorLine == nil)
            #expect(decoded.recentEdits.isEmpty)
            #expect(decoded.recentNavigation.isEmpty)
            #expect(decoded.buildStatus == nil)
        }

        @Test("encodes and decodes populated context")
        func populatedContext() throws {
            let context = FlowContext(
                activeFile: "/src/main.swift",
                cursorLine: 42,
                recentEdits: [
                    FileEvent(path: "/src/main.swift", type: .modified),
                    FileEvent(path: "/src/utils.swift", type: .created)
                ],
                recentNavigation: ["/src/app.swift", "/src/model.swift"],
                buildStatus: BuildStatus(
                    succeeded: false,
                    errorCount: 2,
                    warningCount: 1,
                    errors: ["error: type 'Foo' not found", "error: missing return"]
                ),
                activeScheme: "Undertow",
                activeDestination: "My Mac",
                workspaceURL: "/Users/dev/undertow"
            )

            let data = try JSONEncoder().encode(context)
            let decoded = try JSONDecoder().decode(FlowContext.self, from: data)

            #expect(decoded.activeFile == "/src/main.swift")
            #expect(decoded.cursorLine == 42)
            #expect(decoded.recentEdits.count == 2)
            #expect(decoded.recentNavigation.count == 2)
            #expect(decoded.buildStatus?.succeeded == false)
            #expect(decoded.buildStatus?.errorCount == 2)
            #expect(decoded.buildStatus?.errors.count == 2)
            #expect(decoded.activeScheme == "Undertow")
            #expect(decoded.activeDestination == "My Mac")
            #expect(decoded.workspaceURL == "/Users/dev/undertow")
        }

        @Test("timestamp round-trips correctly")
        func timestampRoundTrip() throws {
            let now = Date.now
            let context = FlowContext(timestamp: now)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try encoder.encode(context)
            let decoded = try decoder.decode(FlowContext.self, from: data)

            // Within 1 second (iso8601 loses sub-second precision)
            #expect(abs(decoded.timestamp.timeIntervalSince(now)) < 1.0)
        }
    }

    // MARK: - FileEvent

    @Suite("FileEvent")
    struct FileEventTests {
        @Test("event types encode correctly")
        func eventTypes() throws {
            let events: [FileEvent] = [
                FileEvent(path: "a.swift", type: .created),
                FileEvent(path: "b.swift", type: .modified),
                FileEvent(path: "c.swift", type: .deleted),
                FileEvent(path: "d.swift", type: .renamed),
            ]

            for event in events {
                let data = try JSONEncoder().encode(event)
                let decoded = try JSONDecoder().decode(FileEvent.self, from: data)
                #expect(decoded.path == event.path)
                #expect(decoded.type == event.type)
            }
        }
    }

    // MARK: - BuildStatus

    @Suite("BuildStatus")
    struct BuildStatusTests {
        @Test("successful build")
        func successfulBuild() {
            let status = BuildStatus(succeeded: true)
            #expect(status.succeeded)
            #expect(status.errorCount == 0)
            #expect(status.warningCount == 0)
            #expect(status.errors.isEmpty)
        }

        @Test("failed build with errors")
        func failedBuild() throws {
            let status = BuildStatus(
                succeeded: false,
                errorCount: 3,
                warningCount: 5,
                errors: ["error: foo", "error: bar", "error: baz"]
            )

            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(BuildStatus.self, from: data)

            #expect(!decoded.succeeded)
            #expect(decoded.errorCount == 3)
            #expect(decoded.warningCount == 5)
            #expect(decoded.errors == ["error: foo", "error: bar", "error: baz"])
        }
    }
}
