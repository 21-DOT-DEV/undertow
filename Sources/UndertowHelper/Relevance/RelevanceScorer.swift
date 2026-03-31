import Foundation
import FoundationModels
import UndertowKit

/// Scores code chunks for relevance using a combination of BM25 text search
/// and on-device Foundation Models for semantic understanding.
///
/// Falls back to BM25-only scoring when Foundation Models is unavailable.
actor RelevanceScorer {
    private var scoreCache: [String: Int] = [:]
    private let maxCacheSize = 500

    // MARK: - BM25 Text Search

    /// Pre-filter chunks using BM25 scoring.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - chunks: All available code chunks.
    ///   - topK: Number of top results to return.
    /// - Returns: Top-k chunks sorted by BM25 score.
    func bm25Filter(query: String, chunks: [CodeChunk], topK: Int = 50) -> [CodeChunk] {
        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty else { return Array(chunks.prefix(topK)) }

        // Compute IDF for each term
        let totalDocs = Double(chunks.count)
        var idf: [String: Double] = [:]
        for term in queryTerms {
            let docsContaining = Double(chunks.filter { chunkContains($0, term: term) }.count)
            idf[term] = log((totalDocs - docsContaining + 0.5) / (docsContaining + 0.5) + 1.0)
        }

        // Compute average document length
        let avgDL = chunks.map { Double(wordCount($0)) }.reduce(0, +) / max(totalDocs, 1)

        // BM25 parameters
        let k1 = 1.2
        let b = 0.75

        // Score each chunk
        var scored: [(chunk: CodeChunk, score: Double)] = chunks.map { chunk in
            let dl = Double(wordCount(chunk))
            var score = 0.0

            for term in queryTerms {
                let tf = Double(termFrequency(chunk, term: term))
                let termIDF = idf[term] ?? 0
                let numerator = tf * (k1 + 1)
                let denominator = tf + k1 * (1 - b + b * dl / max(avgDL, 1))
                score += termIDF * numerator / denominator
            }

            // Boost for query terms appearing in the signature
            let sigLower = chunk.signature.lowercased()
            for term in queryTerms where sigLower.contains(term) {
                score *= 1.5
            }

            return (chunk, score)
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(topK).map(\.chunk)
    }

    // MARK: - Foundation Models Scoring

    /// Score chunks using Foundation Models for semantic relevance.
    ///
    /// - Parameters:
    ///   - query: The natural language query.
    ///   - candidates: Pre-filtered candidate chunks from BM25.
    ///   - topK: Number of top results to return.
    /// - Returns: Scored and ranked chunks, or BM25-only results if LLM unavailable.
    func score(
        query: String,
        candidates: [CodeChunk],
        topK: Int = 10
    ) async -> [ChunkRelevance] {
        // Check if Foundation Models is available
        guard SystemLanguageModel.default.isAvailable else {
            fputs("RelevanceScorer: Foundation Models unavailable, using BM25 only\n", stderr)
            return bm25FallbackResults(query: query, candidates: candidates, topK: topK)
        }

        // Score in parallel with a TaskGroup
        var results: [ChunkRelevance] = []

        await withTaskGroup(of: ChunkRelevance?.self) { group in
            for candidate in candidates.prefix(20) {
                group.addTask { [self] in
                    await self.scoreChunk(query: query, chunk: candidate)
                }
            }

            for await result in group {
                if let result {
                    results.append(result)
                }
            }
        }

        // Sort by score descending and return top-k
        results.sort { $0.score > $1.score }
        return Array(results.prefix(topK))
    }

    private func scoreChunk(query: String, chunk: CodeChunk) async -> ChunkRelevance? {
        // Check cache
        let cacheKey = "\(query.hashValue):\(chunk.id.hashValue)"
        if let cachedScore = scoreCache[cacheKey] {
            return ChunkRelevance(
                score: cachedScore,
                reason: "cached",
                chunk: chunk,
                source: .semantic
            )
        }

        do {
            let session = LanguageModelSession(instructions: """
                You are a code relevance scorer. Given a search query and a code chunk, \
                rate how relevant the code is to the query on a scale of 0-10.
                """)

            let prompt = """
                Query: \(query)

                Code (\(chunk.filePath), lines \(chunk.lineRange.lowerBound)-\(chunk.lineRange.upperBound)):
                \(chunk.signature)
                \(String(chunk.source.prefix(500)))

                Rate relevance 0-10 and explain briefly.
                """

            let response = try await session.respond(
                to: prompt,
                generating: ScoredChunk.self
            )

            let scored = response.content
            let clampedScore = max(0, min(10, scored.score))

            // Cache the result
            cacheScore(key: cacheKey, score: clampedScore)

            return ChunkRelevance(
                score: clampedScore,
                reason: scored.reason,
                chunk: chunk,
                source: .semantic
            )
        } catch {
            fputs("RelevanceScorer: LLM scoring failed: \(error)\n", stderr)
            return nil
        }
    }

    // MARK: - Fallback

    private func bm25FallbackResults(
        query: String,
        candidates: [CodeChunk],
        topK: Int
    ) -> [ChunkRelevance] {
        // Assign scores based on BM25 rank position
        candidates.prefix(topK).enumerated().map { index, chunk in
            ChunkRelevance(
                score: max(10 - index, 1),
                reason: "BM25 rank #\(index + 1)",
                chunk: chunk,
                source: .bm25
            )
        }
    }

    // MARK: - Cache

    private func cacheScore(key: String, score: Int) {
        if scoreCache.count >= maxCacheSize {
            // Evict oldest entries (simple FIFO approximation)
            let keysToRemove = Array(scoreCache.keys.prefix(maxCacheSize / 4))
            for k in keysToRemove { scoreCache.removeValue(forKey: k) }
        }
        scoreCache[key] = score
    }

    // MARK: - Text Processing

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private func wordCount(_ chunk: CodeChunk) -> Int {
        chunk.source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    private func chunkContains(_ chunk: CodeChunk, term: String) -> Bool {
        chunk.source.lowercased().contains(term) || chunk.signature.lowercased().contains(term)
    }

    private func termFrequency(_ chunk: CodeChunk, term: String) -> Int {
        let lower = chunk.source.lowercased()
        var count = 0
        var searchRange = lower.startIndex..<lower.endIndex
        while let range = lower.range(of: term, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lower.endIndex
        }
        return count
    }
}

// MARK: - Generable Types for Foundation Models

@Generable
struct ScoredChunk: Sendable {
    @Guide(description: "Relevance score from 0 (irrelevant) to 10 (highly relevant)", .range(0...10))
    var score: Int

    @Guide(description: "One sentence explaining why this code is relevant to the query")
    var reason: String
}
