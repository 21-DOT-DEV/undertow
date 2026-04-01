import Foundation
import SwiftParser
import SwiftSyntax

/// Parses source files into `CodeChunk` objects for indexing and retrieval.
///
/// For Swift files, uses SwiftSyntax to extract semantic chunks (functions, types, extensions).
/// For non-Swift files, falls back to line-based chunking with overlapping windows.
public struct CodeChunker: Sendable {
    /// Window size for line-based chunking of non-Swift files.
    private let windowSize: Int

    /// Overlap between windows for line-based chunking.
    private let overlapSize: Int

    public init(windowSize: Int = 50, overlapSize: Int = 10) {
        self.windowSize = windowSize
        self.overlapSize = overlapSize
    }

    /// Chunk a single file into `CodeChunk` objects.
    ///
    /// - Parameters:
    ///   - filePath: Path to the file, relative to the project root.
    ///   - source: The file's source content.
    /// - Returns: An array of extracted code chunks.
    public func chunk(filePath: String, source: String) -> [CodeChunk] {
        let ext = (filePath as NSString).pathExtension.lowercased()

        if ext == "swift" {
            return chunkSwift(filePath: filePath, source: source)
        } else {
            return chunkByLines(filePath: filePath, source: source)
        }
    }

    /// Chunk all Swift files in a directory recursively.
    ///
    /// - Parameters:
    ///   - projectRoot: Absolute path to the project root.
    ///   - excludePatterns: Path patterns to exclude (e.g., "DerivedData", ".build").
    /// - Returns: All extracted chunks.
    public func chunkProject(
        at projectRoot: String,
        excludePatterns: [String] = ["DerivedData", ".build", ".git", "Derived"]
    ) -> [CodeChunk] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return [] }

        var allChunks: [CodeChunk] = []

        while let relativePath = enumerator.nextObject() as? String {
            // Skip excluded directories
            if excludePatterns.contains(where: { relativePath.contains($0) }) {
                continue
            }

            let ext = (relativePath as NSString).pathExtension.lowercased()
            let supportedExtensions = ["swift", "h", "m", "mm", "c", "cpp", "json", "yaml", "yml", "md"]
            guard supportedExtensions.contains(ext) else { continue }

            let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)
            guard let source = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            let chunks = chunk(filePath: relativePath, source: source)
            allChunks.append(contentsOf: chunks)
        }

        return allChunks
    }

    // MARK: - Swift Chunking

    private func chunkSwift(filePath: String, source: String) -> [CodeChunk] {
        let tree = Parser.parse(source: source)
        let visitor = SwiftChunkVisitor(filePath: filePath, tree: tree)
        return visitor.extractChunks(from: tree)
    }

    // MARK: - Line-Based Chunking

    private func chunkByLines(filePath: String, source: String) -> [CodeChunk] {
        guard !source.isEmpty else { return [] }
        let lines = source.components(separatedBy: "\n")

        var chunks: [CodeChunk] = []
        var start = 0

        while start < lines.count {
            let end = min(start + windowSize - 1, lines.count - 1)
            let windowLines = Array(lines[start...end])
            let windowSource = windowLines.joined(separator: "\n")

            // Use the first non-empty line as the signature
            let signature = windowLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? "lines \(start + 1)-\(end + 1)"

            chunks.append(CodeChunk(
                filePath: filePath,
                lineRange: (start + 1)...(end + 1), // 1-based
                signature: String(signature.prefix(100)),
                source: windowSource
            ))

            let step = windowSize - overlapSize
            start += max(step, 1)
        }

        return chunks
    }
}
