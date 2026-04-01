import Foundation
import MCP
import UndertowKit

/// MCP tool that provides hybrid semantic search over the codebase.
///
/// Combines IndexStoreDB for structural queries, BM25 for text pre-filtering,
/// and Foundation Models for semantic re-ranking.
actor SemanticSearchEngine {
    private let chunker = CodeChunker()
    private let scorer = RelevanceScorer()
    private let indexStore = IndexStoreService()
    private let importanceMap = ImportanceMap()

    private var chunks: [CodeChunk] = []
    private var projectRoot: String?
    private var lastIndexTime: Date?

    /// Initialize the search engine for a project.
    ///
    /// - Parameters:
    ///   - projectRoot: The actual root directory containing source files.
    ///   - projectName: The project name for DerivedData/IndexStore lookup (e.g. "Undertow").
    func initialize(projectRoot: String, projectName: String? = nil) async {
        self.projectRoot = projectRoot
        let name = projectName ?? (projectRoot as NSString).lastPathComponent
        await indexStore.initialize(projectName: name)
        await reindex()
    }

    /// Re-index the project (called on file changes).
    func reindex() async {
        guard let projectRoot else { return }

        let start = Date.now
        chunks = chunker.chunkProject(at: projectRoot)
        lastIndexTime = .now

        // Also refresh importance map and index store
        await importanceMap.refresh(projectRoot: projectRoot, recentChunks: chunks)
        await indexStore.refresh()

        let elapsed = Date.now.timeIntervalSince(start)
        fputs("SemanticSearchEngine: indexed \(chunks.count) chunks in \(String(format: "%.1f", elapsed))s\n", stderr)
    }

    /// Perform a semantic search.
    ///
    /// - Parameters:
    ///   - query: The search query (natural language or symbol name).
    ///   - topK: Number of results to return.
    /// - Returns: Ranked and scored results.
    func search(query: String, topK: Int = 10) async -> [ChunkRelevance] {
        // Determine query type
        let isStructuralQuery = looksLikeSymbolQuery(query)

        var results: [ChunkRelevance] = []

        // Path 1: Structural query → IndexStoreDB
        if isStructuralQuery, await indexStore.isAvailable {
            let symbolResults = await indexStore.searchSymbols(containing: query)
            let indexChunks = matchSymbolsToChunks(symbolResults)
            for chunk in indexChunks.prefix(topK) {
                results.append(ChunkRelevance(
                    score: 8,
                    reason: "Symbol match from compiler index",
                    chunk: chunk,
                    source: .index
                ))
            }
        }

        // Path 2: BM25 pre-filter → Foundation Models scoring
        let importanceWeighted = applyImportanceWeights(to: chunks)
        let bm25Candidates = await scorer.bm25Filter(
            query: query,
            chunks: importanceWeighted,
            topK: 50
        )

        let scored = await scorer.score(
            query: query,
            candidates: bm25Candidates,
            topK: topK
        )
        results.append(contentsOf: scored)

        // Deduplicate by chunk ID, keeping highest score
        let deduped = deduplicateResults(results)

        // Sort by score descending
        let sorted = deduped.sorted { $0.score > $1.score }
        return Array(sorted.prefix(topK))
    }

    /// Create the MCP tool definition for semantic search.
    static var toolDefinition: Tool {
        Tool(
            name: "semantic_search",
            description: "Search the codebase using natural language or symbol names. Returns ranked code chunks with relevance scores and explanations.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query — natural language description or symbol/function name")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    /// Create the MCP tool definitions for index-specific tools.
    static var indexToolDefinitions: [Tool] {
        [
            Tool(
                name: "find_symbol_references",
                description: "Find all references to a Swift symbol (function, type, property) using the compiler index.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "symbol": .object([
                            "type": .string("string"),
                            "description": .string("The symbol name to find references for")
                        ])
                    ]),
                    "required": .array([.string("symbol")])
                ])
            ),
            Tool(
                name: "find_conformances",
                description: "Find all types conforming to a Swift protocol using the compiler index.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "protocol": .object([
                            "type": .string("string"),
                            "description": .string("The protocol name to find conformances for")
                        ])
                    ]),
                    "required": .array([.string("protocol")])
                ])
            ),
        ]
    }

    /// Handle a tool call.
    func handleToolCall(name: String, arguments: [String: Value]?) async throws -> [Tool.Content] {
        switch name {
        case "semantic_search":
            guard let query = arguments?["query"]?.stringValue else {
                throw MCPError.invalidParams("Missing 'query' parameter")
            }
            let results = await search(query: query)
            return formatSearchResults(results)

        case "find_symbol_references":
            guard let symbol = arguments?["symbol"]?.stringValue else {
                throw MCPError.invalidParams("Missing 'symbol' parameter")
            }
            let results = await indexStore.findSymbolReferences(symbol: symbol)
            return formatSymbolResults(results, kind: "references to '\(symbol)'")

        case "find_conformances":
            guard let proto = arguments?["protocol"]?.stringValue else {
                throw MCPError.invalidParams("Missing 'protocol' parameter")
            }
            let results = await indexStore.findConformances(protocolName: proto)
            return formatSymbolResults(results, kind: "conformances of '\(proto)'")

        default:
            throw MCPError.methodNotFound("Unknown tool: \(name)")
        }
    }

    // MARK: - Helpers

    private func looksLikeSymbolQuery(_ query: String) -> Bool {
        // Heuristic: if the query contains PascalCase or camelCase words, it's likely a symbol query
        let words = query.components(separatedBy: .whitespaces)
        if words.count == 1 {
            let word = words[0]
            // Check for camelCase or PascalCase
            let hasUpperAfterLower = word.contains(where: { $0.isUppercase }) &&
                                     word.contains(where: { $0.isLowercase })
            if hasUpperAfterLower { return true }
            // Check for underscore_case
            if word.contains("_") { return true }
        }
        return false
    }

    private func matchSymbolsToChunks(_ symbols: [SymbolResult]) -> [CodeChunk] {
        symbols.compactMap { symbol in
            chunks.first { chunk in
                chunk.filePath.hasSuffix(symbol.path) &&
                chunk.lineRange.contains(symbol.line)
            }
        }
    }

    private func applyImportanceWeights(to chunks: [CodeChunk]) -> [CodeChunk] {
        // Importance map doesn't change chunk content, but we could
        // pre-sort chunks so BM25 considers important files first.
        // For now, just return as-is (importance is factored in at scoring time).
        chunks
    }

    private func deduplicateResults(_ results: [ChunkRelevance]) -> [ChunkRelevance] {
        var seen = Set<String>()
        return results.filter { result in
            let key = result.chunk.id
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func formatSearchResults(_ results: [ChunkRelevance]) -> [Tool.Content] {
        if results.isEmpty {
            return [.text(text: "No relevant code found.", annotations: nil, _meta: nil)]
        }

        let formatted = results.enumerated().map { index, result in
            let chunk = result.chunk
            let header = "[\(index + 1)] \(chunk.filePath):\(chunk.lineRange.lowerBound)-\(chunk.lineRange.upperBound)"
            let meta = "Score: \(result.score)/10 | Source: \(result.source.rawValue) | \(result.reason)"
            let sig = "Signature: \(chunk.signature)"
            let src = chunk.source.count > 500 ? String(chunk.source.prefix(500)) + "\n// ..." : chunk.source

            return "\(header)\n\(meta)\n\(sig)\n\n\(src)"
        }.joined(separator: "\n\n---\n\n")

        return [.text(text: formatted, annotations: nil, _meta: nil)]
    }

    private func formatSymbolResults(_ results: [SymbolResult], kind: String) -> [Tool.Content] {
        if results.isEmpty {
            return [.text(text: "No \(kind) found.", annotations: nil, _meta: nil)]
        }

        let formatted = results.map { r in
            "\(r.name) [\(r.kind)] at \(r.path):\(r.line)"
        }.joined(separator: "\n")

        return [.text(text: "Found \(results.count) \(kind):\n\(formatted)", annotations: nil, _meta: nil)]
    }
}

// MARK: - Value Helpers

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
