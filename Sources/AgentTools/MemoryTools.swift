// AgentTools/MemoryTools.swift
// Memory tools using AgentRunKit + our VectorStore
// Enables autonomous memory search and storage

import Foundation
import AgentRunKit
import AgentRAG

// MARK: - Context

/// Shared context for memory tools
public struct MemoryToolsContext: ToolContext {
    public let vectorStore: VectorStore
    public let embedder: EmbeddingProvider

    public init(vectorStore: VectorStore, embedder: EmbeddingProvider) {
        self.vectorStore = vectorStore
        self.embedder = embedder
    }
}

// MARK: - Memory Search Tool

/// Parameters for memory search
public struct MemorySearchParams: Codable, Sendable, SchemaProviding {
    /// What to search for (natural language query)
    public let query: String

    /// Number of results to return (1-20)
    public let topK: Int?

    /// Minimum similarity threshold 0.0-1.0
    public let minSimilarity: Double?

    /// Optional tags to filter by
    public let tags: [String]?

    public init(query: String, topK: Int? = nil, minSimilarity: Double? = nil, tags: [String]? = nil) {
        self.query = query
        self.topK = topK
        self.minSimilarity = minSimilarity
        self.tags = tags
    }
}

/// Create memory search tool
public func createMemorySearchTool() throws -> Tool<MemorySearchParams, String, MemoryToolsContext> {
    try Tool(
        name: "search_memory",
        description: """
        Search long-term memory for relevant information using semantic similarity.

        Use this when you need to:
        - Recall past conversations or interactions
        - Find relevant context about a topic
        - Remember user preferences or information
        - Look up previously discussed concepts

        The search uses AI embeddings for semantic matching, not just keywords.
        For example, searching "authentication" will also find "login", "security", etc.
        """
    ) { params, context in
        let topK = params.topK ?? 5
        let minSimilarity = params.minSimilarity ?? 0.5  // Lowered from 0.7 to improve semantic matching

        // Validate parameters
        guard topK >= 1 && topK <= 20 else {
            return "Error: topK must be between 1 and 20"
        }

        guard minSimilarity >= 0.0 && minSimilarity <= 1.0 else {
            return "Error: minSimilarity must be between 0.0 and 1.0"
        }

        // Generate embedding for query
        let queryEmbedding = try await context.embedder.embed(text: params.query)

        // Build filter if tags provided
        let filter: (@Sendable (VectorMetadata) -> Bool)?
        if let filterTags = params.tags {
            filter = { metadata in
                !Set(metadata.tags).isDisjoint(with: Set(filterTags))
            }
        } else {
            filter = nil
        }

        // Search vector store
        let results = try await context.vectorStore.search(
            embedding: queryEmbedding,
            topK: topK,
            minSimilarity: minSimilarity,
            filter: filter
        )

        // Debug logging
        print("🔍 [MemorySearch] Query: \"\(params.query)\"")
        print("🔍 [MemorySearch] Threshold: \(Int(minSimilarity * 100))%, TopK: \(topK)")
        print("🔍 [MemorySearch] Found \(results.count) results")
        for (i, result) in results.prefix(3).enumerated() {
            let preview = String(result.metadata.text.prefix(60))
            print("🔍 [MemorySearch] [\(i+1)] \(Int(result.similarity * 100))% - \(preview)...")
        }

        // Format results
        if results.isEmpty {
            return """
            🔍 Memory Search: No relevant memories found

            Query: "\(params.query)"
            Threshold: \(Int(minSimilarity * 100))% similarity

            Try lowering min_similarity or rephrasing your query.
            """
        }

        var output = "🧠 Memory Search Results (\(results.count) found)\n\n"
        output += "Query: \"\(params.query)\"\n"
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

            output += "\n"
        }

        return output
    }
}

// MARK: - Memory Store Tool

/// Parameters for storing memory
public struct MemoryStoreParams: Codable, Sendable, SchemaProviding {
    /// Information to store
    public let information: String

    /// Categories/tags for this memory
    public let tags: [String]

    /// Importance level 1-10
    public let importance: Int?

    public init(information: String, tags: [String], importance: Int? = nil) {
        self.information = information
        self.tags = tags
        self.importance = importance
    }
}

/// Create memory store tool
public func createMemoryStoreTool() throws -> Tool<MemoryStoreParams, String, MemoryToolsContext> {
    try Tool(
        name: "store_memory",
        description: """
        Store important information in long-term memory for future reference.

        Use this when:
        - The user shares important preferences or information
        - You learn something that will be useful later
        - You need to remember context across conversations
        - You want to build a knowledge base

        Examples:
        - User preferences (e.g., "prefers React over Vue")
        - Technical facts (e.g., "uses JWT tokens with 24h expiry")
        - Important context (e.g., "works in fintech industry")
        """
    ) { params, context in
        let importance = params.importance ?? 5

        // Validate parameters
        guard !params.information.isEmpty else {
            return "Error: information cannot be empty"
        }

        guard !params.tags.isEmpty else {
            return "Error: at least one tag is required"
        }

        guard importance >= 1 && importance <= 10 else {
            return "Error: importance must be between 1 and 10"
        }

        // Generate embedding
        let embedding = try await context.embedder.embed(text: params.information)

        // Create metadata
        let metadata = VectorMetadata(
            text: params.information,
            timestamp: Date(),
            tags: params.tags,
            customData: [
                "importance": String(importance),
                "stored_at": ISO8601DateFormatter().string(from: Date())
            ]
        )

        // Store in vector database
        try await context.vectorStore.insert(embedding: embedding, metadata: metadata)

        return """
        💾 Memory Stored Successfully

        Information: "\(params.information)"
        Tags: \(params.tags.joined(separator: ", "))
        Importance: \(importance)/10
        ID: \(metadata.id)

        This information is now searchable using search_memory.
        """
    }
}

// MARK: - Helper Functions

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
