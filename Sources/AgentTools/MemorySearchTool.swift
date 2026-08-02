// AgentTools/MemorySearchTool.swift
// Semantic memory search tool using VectorStore
// Enables agents to search their long-term memory autonomously

import Foundation
import AgentCore
import AgentRAG

/// Tool for searching semantic memory using vector embeddings
/// The agent uses this automatically to find relevant context from past conversations
public struct MemorySearchTool: AgentTool {
    public let name = "search_memory"
    public let description = """
    Search your long-term memory for relevant information using semantic similarity.

    Use this when you need to:
    - Recall past conversations or interactions
    - Find relevant context about a topic
    - Remember user preferences or information
    - Look up previously discussed concepts

    The search uses AI embeddings to find semantically similar content,
    not just keyword matching. For example, searching "authentication"
    will also find content about "login", "security", "passwords", etc.

    Parameters:
    - query: What you're looking for (be specific and descriptive)
    - top_k: How many results to return (default: 5)
    - min_similarity: Minimum relevance score 0.0-1.0 (default: 0.7)
    """

    private let _inputSchema = SchemaWrapper([
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "What you're searching for - be specific and use natural language"
            ],
            "top_k": [
                "type": "integer",
                "description": "Number of results to return (1-20)",
                "default": 5
            ],
            "min_similarity": [
                "type": "number",
                "description": "Minimum similarity threshold 0.0-1.0 (higher = more strict)",
                "default": 0.7
            ],
            "tags": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional: Filter by tags (e.g., ['user_preference', 'technical'])"
            ]
        ],
        "required": ["query"]
    ])

    public var inputSchema: [String: Any] {
        _inputSchema.value
    }

    private let vectorStore: VectorStore
    private let embedder: EmbeddingProvider

    public init(vectorStore: VectorStore, embedder: EmbeddingProvider) {
        self.vectorStore = vectorStore
        self.embedder = embedder
    }

    public func execute(parameters: [String: Any]) async throws -> String {
        guard let query = parameters["query"] as? String else {
            throw ToolError.invalidParameters("'query' parameter is required")
        }

        let topK = parameters["top_k"] as? Int ?? 5
        let minSimilarity = parameters["min_similarity"] as? Double ?? 0.7
        let filterTags = parameters["tags"] as? [String]

        // Validate parameters
        guard topK >= 1 && topK <= 20 else {
            throw ToolError.invalidParameters("top_k must be between 1 and 20")
        }

        guard minSimilarity >= 0.0 && minSimilarity <= 1.0 else {
            throw ToolError.invalidParameters("min_similarity must be between 0.0 and 1.0")
        }

        // Generate embedding for the query
        let queryEmbedding = try await embedder.embed(text: query)

        // Build filter if tags provided
        let filter: (@Sendable (VectorMetadata) -> Bool)?
        if let filterTags = filterTags {
            filter = { metadata in
                !Set(metadata.tags).isDisjoint(with: Set(filterTags))
            }
        } else {
            filter = nil
        }

        // Search vector store
        let results = try await vectorStore.search(
            embedding: queryEmbedding,
            topK: topK,
            minSimilarity: minSimilarity,
            filter: filter
        )

        // Format results
        if results.isEmpty {
            return """
            🔍 Memory Search: No relevant memories found

            Query: "\(query)"
            Threshold: \(Int(minSimilarity * 100))% similarity

            This might mean:
            - No information has been stored about this topic yet
            - Try lowering min_similarity to find less relevant results
            - Try rephrasing your query with different keywords
            """
        }

        var output = "🧠 Memory Search Results (\(results.count) found)\n\n"
        output += "Query: \"\(query)\"\n"
        output += "Similarity threshold: \(Int(minSimilarity * 100))%\n\n"

        for (index, result) in results.enumerated() {
            let percentage = Int(result.similarity * 100)
            let timeAgo = formatTimeAgo(from: result.metadata.timestamp)

            output += "[\(index + 1)] [\(percentage)% match] \(timeAgo)\n"
            output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            output += "\(result.metadata.text)\n"

            if !result.metadata.tags.isEmpty {
                output += "\n🏷️  Tags: \(result.metadata.tags.joined(separator: ", "))\n"
            }

            if !result.metadata.customData.isEmpty {
                output += "📊 Metadata: \(result.metadata.customData.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))\n"
            }

            output += "\n"
        }

        return output
    }

    /// Format timestamp as human-readable relative time
    private func formatTimeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if interval < 2592000 {
            let weeks = Int(interval / 604800)
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else {
            let months = Int(interval / 2592000)
            return "\(months) month\(months == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - JSON Schema Wrapper

private struct SchemaWrapper: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) {
        self.value = value
    }
}
