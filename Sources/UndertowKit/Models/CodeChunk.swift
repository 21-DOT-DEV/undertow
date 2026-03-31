import Foundation

/// A chunk of source code extracted by the code chunker.
///
/// Represents a function, type, extension, or other meaningful
/// unit of code for relevance scoring and retrieval.
public struct CodeChunk: Codable, Sendable, Identifiable {
    public var id: String { "\(filePath):\(lineRange.lowerBound)-\(lineRange.upperBound)" }

    /// Path to the source file, relative to the project root.
    public var filePath: String

    /// Line range within the file (1-based, inclusive).
    public var lineRange: ClosedRange<Int>

    /// The function/type signature or first meaningful line.
    public var signature: String

    /// Doc comments associated with this chunk.
    public var docComment: String?

    /// The containing type name, if this chunk is a method or nested type.
    public var containingType: String?

    /// The raw source code of the chunk.
    public var source: String

    public init(
        filePath: String,
        lineRange: ClosedRange<Int>,
        signature: String,
        docComment: String? = nil,
        containingType: String? = nil,
        source: String
    ) {
        self.filePath = filePath
        self.lineRange = lineRange
        self.signature = signature
        self.docComment = docComment
        self.containingType = containingType
        self.source = source
    }
}
