import Foundation
import Testing
@testable import UndertowKit

@Suite("Models")
struct ModelTests {

    // MARK: - CodeChunk

    @Suite("CodeChunk")
    struct CodeChunkTests {
        @Test("id combines file path and line range")
        func idFormat() {
            let chunk = CodeChunk(
                filePath: "Sources/App.swift",
                lineRange: 10...25,
                signature: "struct App",
                source: "struct App {}"
            )
            #expect(chunk.id == "Sources/App.swift:10-25")
        }

        @Test("id is unique for different ranges in same file")
        func uniqueIds() {
            let chunk1 = CodeChunk(
                filePath: "File.swift", lineRange: 1...5,
                signature: "func a", source: ""
            )
            let chunk2 = CodeChunk(
                filePath: "File.swift", lineRange: 7...12,
                signature: "func b", source: ""
            )
            #expect(chunk1.id != chunk2.id)
        }

        @Test("id is unique for different files at same range")
        func uniqueIdsAcrossFiles() {
            let chunk1 = CodeChunk(
                filePath: "A.swift", lineRange: 1...5,
                signature: "func x", source: ""
            )
            let chunk2 = CodeChunk(
                filePath: "B.swift", lineRange: 1...5,
                signature: "func x", source: ""
            )
            #expect(chunk1.id != chunk2.id)
        }

        @Test("codable round-trip")
        func codable() throws {
            let chunk = CodeChunk(
                filePath: "src/Model.swift",
                lineRange: 3...15,
                signature: "class Model: Codable",
                docComment: "/// The main model.",
                containingType: nil,
                source: "class Model: Codable { var id: Int }"
            )

            let data = try JSONEncoder().encode(chunk)
            let decoded = try JSONDecoder().decode(CodeChunk.self, from: data)

            #expect(decoded.filePath == chunk.filePath)
            #expect(decoded.lineRange == chunk.lineRange)
            #expect(decoded.signature == chunk.signature)
            #expect(decoded.docComment == chunk.docComment)
            #expect(decoded.containingType == chunk.containingType)
            #expect(decoded.source == chunk.source)
        }

        @Test("optional fields default to nil")
        func optionalDefaults() {
            let chunk = CodeChunk(
                filePath: "f.swift", lineRange: 1...1,
                signature: "let x", source: "let x = 1"
            )
            #expect(chunk.docComment == nil)
            #expect(chunk.containingType == nil)
        }
    }

    // MARK: - ChunkRelevance

    @Suite("ChunkRelevance")
    struct ChunkRelevanceTests {
        @Test("codable round-trip")
        func codable() throws {
            let chunk = CodeChunk(
                filePath: "test.swift", lineRange: 1...3,
                signature: "func test", source: "func test() {}"
            )
            let relevance = ChunkRelevance(
                score: 8,
                reason: "Directly implements the requested feature",
                chunk: chunk,
                source: .semantic
            )

            let data = try JSONEncoder().encode(relevance)
            let decoded = try JSONDecoder().decode(ChunkRelevance.self, from: data)

            #expect(decoded.score == 8)
            #expect(decoded.reason == "Directly implements the requested feature")
            #expect(decoded.source == .semantic)
            #expect(decoded.chunk.filePath == "test.swift")
        }

        @Test("all result sources encode correctly")
        func resultSources() throws {
            let sources: [ChunkRelevance.ResultSource] = [.index, .semantic, .bm25, .combined]
            let chunk = CodeChunk(
                filePath: "f.swift", lineRange: 1...1,
                signature: "x", source: ""
            )

            for source in sources {
                let relevance = ChunkRelevance(
                    score: 5, reason: "test", chunk: chunk, source: source
                )
                let data = try JSONEncoder().encode(relevance)
                let decoded = try JSONDecoder().decode(ChunkRelevance.self, from: data)
                #expect(decoded.source == source)
            }
        }

        @Test("score clamping is caller responsibility")
        func scoreBounds() {
            let chunk = CodeChunk(
                filePath: "f.swift", lineRange: 1...1,
                signature: "x", source: ""
            )
            // The model doesn't enforce bounds — scoring code should clamp
            let high = ChunkRelevance(score: 15, reason: "", chunk: chunk, source: .bm25)
            let low = ChunkRelevance(score: -1, reason: "", chunk: chunk, source: .bm25)
            #expect(high.score == 15) // No clamping at model level
            #expect(low.score == -1)
        }
    }

    // MARK: - Memory

    @Suite("Memory")
    struct MemoryTests {
        @Test("codable round-trip")
        func codable() throws {
            let memory = Memory(
                content: "This project uses async/await exclusively",
                source: .user,
                tags: ["conventions", "async"]
            )

            let data = try JSONEncoder().encode(memory)
            let decoded = try JSONDecoder().decode(Memory.self, from: data)

            #expect(decoded.content == memory.content)
            #expect(decoded.source == .user)
            #expect(decoded.tags == ["conventions", "async"])
            #expect(decoded.id == memory.id)
        }
    }
}
