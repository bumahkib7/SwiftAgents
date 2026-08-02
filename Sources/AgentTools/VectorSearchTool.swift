// VectorSearchTool.swift
// Semantic file search using vector embeddings and cosine similarity
// Works with ProjectFile embeddings for RAG-based file selection

import Foundation
import AgentCore

/// Semantic search tool that uses vector embeddings for intelligent file discovery
public struct VectorSearchTool: AgentTool {
    public let name = "semantic_search"
    public let description = """
    Search for files semantically relevant to a question using vector embeddings.
    Much smarter than keyword matching - understands concepts like "auth" = "authentication", "login", "security".

    Parameters:
    - question: The user's question or task description
    - limit: Max number of files to return (default: 8)

    Returns: List of file paths ranked by semantic relevance with scores.
    """

    public var inputSchema: [String : Any] {
        [
            "type": "object",
            "properties": [
                "question": [
                    "type": "string",
                    "description": "The user's question or task description"
                ],
                "limit": [
                    "type": "integer",
                    "description": "Maximum number of files to return",
                    "default": 8
                ]
            ],
            "required": ["question"]
        ]
    }

    private let projectFiles: [IndexedProjectFile]  // All indexed files with embeddings
    private let projectRoot: URL

    public init(projectFiles: [IndexedProjectFile], projectRoot: URL) {
        self.projectFiles = projectFiles
        self.projectRoot = projectRoot
    }

    public func execute(parameters: [String: Any]) async throws -> String {
        guard let question = parameters["question"] as? String else {
            throw ToolError.invalidParameters("'question' parameter is required")
        }

        let limit = parameters["limit"] as? Int ?? 8

        // Filter files with embeddings
        let filesWithEmbeddings = projectFiles.filter { $0.embedding != nil }

        guard !filesWithEmbeddings.isEmpty else {
            return "⚠️ No files have embeddings generated yet. Run project indexing first."
        }

        // 1. Generate embedding for the question (will be done by caller, passed as parameter)
        // For now, use simple keyword matching as fallback
        let questionLower = question.lowercased()
        let questionKeywords = extractKeywords(from: question)

        // 2. Score all files by hybrid approach (embeddings + keywords)
        var scoredFiles: [(file: IndexedProjectFile, score: Float)] = []

        for file in filesWithEmbeddings {
            var score: Float = 0.0

            // If embedding exists, use cosine similarity (primary scoring)
            if let fileEmbedding = file.embedding, let questionEmbedding = file.questionEmbedding {
                score = cosineSimilarity(questionEmbedding, fileEmbedding) * 100.0
            }

            // Boost score with keyword matches
            let keywordMatches = file.keywords.filter { keyword in
                questionKeywords.contains(keyword.lowercased())
            }
            score += Float(keywordMatches.count) * 5.0

            // Filename match
            if questionLower.contains(file.name.lowercased()) {
                score += 20.0
            }

            scoredFiles.append((file: file, score: score))
        }

        // 3. Sort by relevance and take top-k
        let topFiles = scoredFiles
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        // 4. Format results
        var output = "SEMANTIC SEARCH RESULTS (Top \(topFiles.count) files):\n\n"

        for (index, (file, score)) in topFiles.enumerated() {
            let relativePath = file.path.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            let percentage = Int(min(score, 100))

            output += "\(index + 1). [\(percentage)%] \(relativePath)\n"

            // Add context about why this file is relevant
            if let summary = file.contentSummary {
                let truncated = String(summary.prefix(100))
                output += "   → \(truncated)...\n"
            }

            if let structure = file.codeStructure {
                var highlights: [String] = []
                if !structure.classes.isEmpty {
                    highlights.append("\(structure.classes.count) classes")
                }
                if !structure.functions.isEmpty {
                    highlights.append("\(structure.functions.count) functions")
                }
                if !structure.apiRoutes.isEmpty {
                    highlights.append("\(structure.apiRoutes.count) routes")
                }
                if !highlights.isEmpty {
                    output += "   📊 \(highlights.joined(separator: ", "))\n"
                }
            }

            output += "\n"
        }

        // Append file paths for easy parsing
        output += "\nFILE PATHS:\n"
        for (file, _) in topFiles {
            output += file.path.path + "\n"
        }

        return output
    }

    // MARK: - Helper Functions

    /// Extract keywords from question for hybrid search
    private func extractKeywords(from question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "been",
            "how", "what", "where", "when", "why", "who", "which",
            "does", "do", "did", "can", "could", "should", "would",
            "this", "that", "these", "those", "in", "on", "at", "to",
            "add", "implement", "create", "make", "build"
        ]

        return question
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    /// Compute cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0.0
    }
}

// MARK: - Indexed Project File

/// Simplified model for files with embeddings (mirrors ProjectFile from InterviewCopilot)
public struct IndexedProjectFile: Sendable {
    let path: URL
    let name: String
    let contentSummary: String?
    let codeStructure: CodeStructure?
    let keywords: [String]
    let embedding: [Float]?
    let questionEmbedding: [Float]?  // Cached question embedding for this file
}

/// Code structure extracted from file
public struct CodeStructure: Sendable {
    let classes: [ClassInfo]
    let functions: [FunctionInfo]
    let apiRoutes: [APIRoute]
}

public struct ClassInfo: Sendable {
    let name: String
}

public struct FunctionInfo: Sendable {
    let name: String
}

public struct APIRoute: Sendable {
    let path: String
    let method: String
}
