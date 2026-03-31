import Foundation
import IndexStoreDB
import UndertowKit

/// Provides symbol-level queries using Xcode's index store.
///
/// Loads the project index from DerivedData and exposes queries
/// for symbol references, conformances, and callers.
actor IndexStoreService {
    private var db: IndexStoreDB?
    private var isInitialized = false

    /// Initialize with a project name to locate its index in DerivedData.
    func initialize(projectName: String) async {
        guard !isInitialized else { return }

        do {
            let storePath = try findIndexStorePath(projectName: projectName)
            let databasePath = UndertowXPC.sharedStateDirectory
                .appendingPathComponent("indexdb-\(projectName)")
                .path

            // Create database directory if needed
            try FileManager.default.createDirectory(
                atPath: databasePath,
                withIntermediateDirectories: true
            )

            let lib = try IndexStoreLibrary(dylibPath: libIndexStorePath())

            db = try IndexStoreDB(
                storePath: storePath,
                databasePath: databasePath,
                library: lib,
                waitUntilDoneInitializing: true
            )

            isInitialized = true
            fputs("IndexStoreService: initialized for \(projectName)\n", stderr)
        } catch {
            fputs("IndexStoreService: failed to initialize: \(error)\n", stderr)
        }
    }

    /// Whether the index is available.
    var isAvailable: Bool { db != nil }

    /// Refresh the index to pick up latest build changes.
    func refresh() {
        db?.pollForUnitChangesAndWait()
    }

    // MARK: - Queries

    /// Find all references to a symbol by name.
    func findSymbolReferences(symbol: String) -> [SymbolResult] {
        guard let db else { return [] }

        let definitions = db.canonicalOccurrences(ofName: symbol)
        guard let definition = definitions.first else { return [] }

        let references = db.occurrences(ofUSR: definition.symbol.usr, roles: .reference)
        return references.map { occ in
            SymbolResult(
                name: occ.symbol.name,
                kind: String(describing: occ.symbol.kind),
                path: occ.location.path,
                line: occ.location.line,
                column: occ.location.utf8Column,
                role: "reference"
            )
        }
    }

    /// Find all types conforming to a protocol.
    func findConformances(protocolName: String) -> [SymbolResult] {
        guard let db else { return [] }

        let definitions = db.canonicalOccurrences(ofName: protocolName)
        guard let definition = definitions.first else { return [] }

        let conformers = db.occurrences(relatedToUSR: definition.symbol.usr, roles: .baseOf)
        return conformers.map { occ in
            SymbolResult(
                name: occ.symbol.name,
                kind: String(describing: occ.symbol.kind),
                path: occ.location.path,
                line: occ.location.line,
                column: occ.location.utf8Column,
                role: "conformance"
            )
        }
    }

    /// Find all direct callers of a function.
    func findCallers(functionName: String) -> [SymbolResult] {
        guard let db else { return [] }

        let definitions = db.canonicalOccurrences(ofName: functionName)
        guard let definition = definitions.first else { return [] }

        let callers = db.occurrences(ofUSR: definition.symbol.usr, roles: .call)
        return callers.map { occ in
            SymbolResult(
                name: occ.symbol.name,
                kind: String(describing: occ.symbol.kind),
                path: occ.location.path,
                line: occ.location.line,
                column: occ.location.utf8Column,
                role: "caller"
            )
        }
    }

    /// Search for symbols matching a pattern.
    func searchSymbols(containing query: String) -> [SymbolResult] {
        guard let db else { return [] }

        let matches = db.canonicalOccurrences(
            containing: query,
            anchorStart: false,
            anchorEnd: false,
            subsequence: false,
            ignoreCase: true
        )

        return matches.prefix(50).map { occ in
            SymbolResult(
                name: occ.symbol.name,
                kind: String(describing: occ.symbol.kind),
                path: occ.location.path,
                line: occ.location.line,
                column: occ.location.utf8Column,
                role: "definition"
            )
        }
    }

    // MARK: - Path Discovery

    private func findIndexStorePath(projectName: String) throws -> String {
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        let contents = try FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        guard let projectDir = contents.first(where: { $0.lastPathComponent.hasPrefix(projectName + "-") }) else {
            throw IndexStoreError.projectNotFound(projectName)
        }

        let storePath = projectDir
            .appendingPathComponent("Index.noindex")
            .appendingPathComponent("DataStore")

        guard FileManager.default.fileExists(atPath: storePath.path) else {
            throw IndexStoreError.indexNotFound(storePath.path)
        }

        return storePath.path
    }

    private func libIndexStorePath() throws -> String {
        // Standard Xcode location for libIndexStore.dylib
        let path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib"
        guard FileManager.default.fileExists(atPath: path) else {
            // Try xcode-select path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["--find", "swift"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let swiftPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let toolchainLib = (swiftPath as NSString)
                    .deletingLastPathComponent
                    .appending("/../lib/libIndexStore.dylib")
                let resolved = (toolchainLib as NSString).standardizingPath
                if FileManager.default.fileExists(atPath: resolved) {
                    return resolved
                }
            }

            throw IndexStoreError.libIndexStoreNotFound
        }
        return path
    }
}

// MARK: - Types

/// A symbol occurrence result from the index.
struct SymbolResult: Codable, Sendable {
    var name: String
    var kind: String
    var path: String
    var line: Int
    var column: Int
    var role: String
}

enum IndexStoreError: Error, LocalizedError {
    case projectNotFound(String)
    case indexNotFound(String)
    case libIndexStoreNotFound

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let name): "DerivedData not found for project '\(name)'"
        case .indexNotFound(let path): "Index store not found at '\(path)'"
        case .libIndexStoreNotFound: "libIndexStore.dylib not found"
        }
    }
}
