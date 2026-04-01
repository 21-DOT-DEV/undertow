import Foundation
import Subprocess
import UndertowKit

/// Pre-computes file importance scores based on edit frequency, git churn,
/// and dependency depth to weight search results.
///
/// Files that are edited more frequently, changed more in git, or imported
/// by many other files are considered more important.
actor ImportanceMap {
    private var scores: [String: Double] = [:]
    private var lastRefresh: Date?

    /// Get the importance score for a file path (0.0 to 1.0).
    func importance(of filePath: String) -> Double {
        scores[filePath] ?? 0.5  // Default to neutral importance
    }

    /// Refresh the importance map for a project.
    func refresh(projectRoot: String, recentChunks: [CodeChunk]) async {
        var newScores: [String: Double] = [:]

        // Factor 1: Recent edit frequency (from chunks, proxy for activity)
        let filePaths = Set(recentChunks.map(\.filePath))
        let editFrequency = computeEditFrequency(projectRoot: projectRoot)

        // Factor 2: Git churn (commits in last 30 days)
        let gitChurn = await computeGitChurn(projectRoot: projectRoot)

        // Factor 3: Import depth (files imported by many others)
        let importDepth = computeImportDepth(chunks: recentChunks)

        // Combine factors with weights
        for path in filePaths {
            let editScore = editFrequency[path] ?? 0.0
            let churnScore = gitChurn[path] ?? 0.0
            let depthScore = importDepth[path] ?? 0.0

            // Weighted combination: edit frequency matters most
            let combined = editScore * 0.4 + churnScore * 0.35 + depthScore * 0.25
            newScores[path] = min(1.0, combined)
        }

        scores = newScores
        lastRefresh = .now
    }

    // MARK: - Edit Frequency

    private func computeEditFrequency(projectRoot: String) -> [String: Double] {
        // Read recent file modification times
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return [:] }

        var modTimes: [String: Date] = [:]
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600) // Last 7 days

        while let path = enumerator.nextObject() as? String {
            let ext = (path as NSString).pathExtension.lowercased()
            guard ["swift", "h", "m", "c", "cpp"].contains(ext) else { continue }
            if path.contains("DerivedData") || path.contains(".build") || path.contains(".git") { continue }

            let fullPath = (projectRoot as NSString).appendingPathComponent(path)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let modDate = attrs[.modificationDate] as? Date,
               modDate > cutoff {
                modTimes[path] = modDate
            }
        }

        guard !modTimes.isEmpty else { return [:] }

        // Normalize: most recently edited = 1.0, oldest = 0.0
        let now = Date.now.timeIntervalSinceReferenceDate
        let maxAge = 7.0 * 24 * 3600
        return modTimes.mapValues { date in
            let age = now - date.timeIntervalSinceReferenceDate
            return max(0, 1.0 - age / maxAge)
        }
    }

    // MARK: - Git Churn

    private func computeGitChurn(projectRoot: String) async -> [String: Double] {
        // Use git log to count commits per file in last 30 days
        let output: String
        do {
            let result = try await Subprocess.run(
                .name("git"),
                arguments: .init([
                    "-C", projectRoot,
                    "log", "--name-only", "--format=", "--since=30.days.ago"
                ]),
                output: .string(limit: 512 * 1024),
                error: .string(limit: 4096)
            )
            guard case .exited(0) = result.terminationStatus,
                  let stdout = result.standardOutput else { return [:] }
            output = stdout
        } catch {
            return [:]
        }

        // Count occurrences of each file
        var counts: [String: Int] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }

        guard let maxCount = counts.values.max(), maxCount > 0 else { return [:] }

        // Normalize to 0.0-1.0
        return counts.mapValues { Double($0) / Double(maxCount) }
    }

    // MARK: - Import Depth

    private func computeImportDepth(chunks: [CodeChunk]) -> [String: Double] {
        // Count how many files import each module/file
        // Simple heuristic: files whose types appear in many other files' signatures
        var fileTypes: [String: Set<String>] = [:]  // file -> types defined in it
        var typeUsage: [String: Int] = [:]  // type name -> number of files using it

        for chunk in chunks {
            if let containingType = chunk.containingType {
                fileTypes[chunk.filePath, default: []].insert(containingType)
            }
            // Also extract type names from signatures
            let sigWords = chunk.signature.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for word in sigWords where word.first?.isUppercase == true && word.count > 2 {
                typeUsage[word, default: 0] += 1
            }
        }

        // Score each file based on how many other files reference its types
        var scores: [String: Double] = [:]
        let maxUsage = Double(typeUsage.values.max() ?? 1)

        for (file, types) in fileTypes {
            let totalUsage = types.reduce(0.0) { sum, type in
                sum + Double(typeUsage[type] ?? 0)
            }
            scores[file] = min(1.0, totalUsage / max(maxUsage * Double(types.count), 1.0))
        }

        return scores
    }
}
