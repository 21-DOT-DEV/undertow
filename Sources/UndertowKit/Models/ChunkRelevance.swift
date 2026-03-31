import Foundation

/// A scored code chunk with a relevance reason.
public struct ChunkRelevance: Codable, Sendable {
    /// The relevance score (0-10).
    public var score: Int

    /// A brief explanation of why this chunk is relevant.
    public var reason: String

    /// The scored code chunk.
    public var chunk: CodeChunk

    /// Where this result came from.
    public var source: ResultSource

    public enum ResultSource: String, Codable, Sendable {
        case index      // From IndexStoreDB
        case semantic   // From Foundation Models scorer
        case bm25       // From BM25 text search
        case combined   // Merged from multiple sources
    }

    public init(score: Int, reason: String, chunk: CodeChunk, source: ResultSource) {
        self.score = score
        self.reason = reason
        self.chunk = chunk
        self.source = source
    }
}
