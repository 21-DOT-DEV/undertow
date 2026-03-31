import Foundation

/// A persistent memory entry that survives across sessions.
public struct Memory: Codable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// Explicitly created by the developer.
        case user
        /// Auto-generated from agent interactions.
        case auto
    }

    public var id: UUID
    public var content: String
    public var source: Source
    public var tags: [String]
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        content: String,
        source: Source,
        tags: [String] = [],
        timestamp: Date = .now
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.tags = tags
        self.timestamp = timestamp
    }
}
