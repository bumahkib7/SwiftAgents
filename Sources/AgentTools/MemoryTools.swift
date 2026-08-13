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

/// Create memory search tool with hybrid search (keyword + semantic + RRF)
public func createMemorySearchTool() throws -> Tool<MemorySearchParams, String, MemoryToolsContext> {
    try Tool(
        name: "search_memory",
        description: """
        Search long-term memory using HYBRID SEARCH (2026 production standard):
        - Keyword matching (TF-IDF) for exact company/project names
        - Semantic search (vector embeddings) for conceptual matches
        - Metadata filtering for company-specific queries
        - Reciprocal Rank Fusion to combine results

        Use this when you need to:
        - Find work experience at specific companies
        - Recall past projects or interactions
        - Look up technical skills or technologies used
        - Remember user preferences or information

        Automatically detects company names and filters results for precision.
        """
    ) { params, context in
        let topK = params.topK ?? 5
        let minSimilarity = params.minSimilarity ?? 0.3  // Lowered to 30% for better recall with Apple NL embeddings

        // Validate parameters
        guard topK >= 1 && topK <= 20 else {
            return "Error: topK must be between 1 and 20"
        }

        guard minSimilarity >= 0.0 && minSimilarity <= 1.0 else {
            return "Error: minSimilarity must be between 0.0 and 1.0"
        }

        // STEP 1: Extract entities from query (companies, skills, etc.)
        let entities = QuestionEntityExtractor.extract(from: params.query)

        // STEP 2: Build metadata filter (pre-filter by company if detected)
        let metadataFilter: (@Sendable (VectorMetadata) -> Bool)?
        if let companyFilter = QuestionEntityExtractor.createMetadataFilter(from: entities) {
            // Combine company filter with tag filter if provided
            if let tagFilter = params.tags {
                let capturedTags = tagFilter  // Capture to make it Sendable
                metadataFilter = { @Sendable metadata in
                    let tagsMatch = !Set(metadata.tags).isDisjoint(with: Set(capturedTags))
                    return tagsMatch && companyFilter(metadata)
                }
            } else {
                metadataFilter = companyFilter
            }
        } else if let tagFilter = params.tags {
            // Just tag filter
            let capturedTags = tagFilter  // Capture to make it Sendable
            metadataFilter = { @Sendable metadata in
                !Set(metadata.tags).isDisjoint(with: Set(capturedTags))
            }
        } else {
            metadataFilter = nil
        }

        print("🔍 [HybridSearch] Query: \"\(params.query)\"")
        if !entities.companies.isEmpty {
            print("🔍 [HybridSearch] Detected companies: \(entities.companies.joined(separator: ", "))")
        }

        // STEP 3a: Get documents for keyword search (limit to reasonable size)
        let queryEmbedding = try await context.embedder.embed(text: params.query)
        let candidateLimit = metadataFilter != nil ? 20 : 50  // Smaller set when filtered by company
        let allDocs = try await context.vectorStore.search(
            embedding: queryEmbedding,
            topK: candidateLimit,
            minSimilarity: 0.0,  // No threshold for candidates
            filter: metadataFilter  // Apply metadata filter
        )

        print("🔍 [HybridSearch] Searching \(allDocs.count) documents (after metadata filter)")

        // STEP 3b: Build TF-IDF index and search keywords
        let tfidfDocuments = allDocs.map { (id: $0.metadata.id, text: $0.metadata.text) }
        let tfidfScorer = HybridSearch.TFIDFScorer(documents: tfidfDocuments)
        let keywordResults = tfidfScorer.search(query: params.query, topK: topK)

        // STEP 3c: Run semantic search (reuse allDocs to avoid duplicate search)
        let semanticResults = allDocs

        // STEP 4: Combine with Reciprocal Rank Fusion (RRF)
        let semanticScores = semanticResults.map { (id: $0.metadata.id, score: $0.similarity) }
        let fusedResults = HybridSearch.reciprocalRankFusion(
            keywordResults: keywordResults,
            semanticResults: semanticScores,
            k: 60  // Standard RRF k value in 2026
        )

        print("🔍 [HybridSearch] Keyword top-3: \(keywordResults.prefix(3).map { "\($0.id): \(String(format: "%.3f", $0.score))" }.joined(separator: ", "))")
        print("🔍 [HybridSearch] Semantic top-3: \(semanticResults.prefix(3).map { "\($0.metadata.id): \(Int($0.similarity * 100))%" }.joined(separator: ", "))")
        print("🔍 [HybridSearch] RRF top-3: \(fusedResults.prefix(3).map { "\($0.id): \(String(format: "%.3f", $0.score))" }.joined(separator: ", "))")

        // STEP 5: Map RRF results back to full metadata
        // Use uniquingKeysWith to handle duplicate IDs (take first occurrence)
        let idToMetadata = Dictionary(
            semanticResults.map { ($0.metadata.id, $0.metadata) },
            uniquingKeysWith: { first, _ in first }
        )
        let finalResults = fusedResults.prefix(topK).compactMap { fusedResult -> (metadata: VectorMetadata, score: Double)? in
            guard let metadata = idToMetadata[fusedResult.id] else { return nil }
            return (metadata: metadata, score: fusedResult.score)
        }

        // Search vector store with VERY LOW threshold to see all candidates (LEGACY - now using RRF)
        let allResults = semanticResults  // For backward compatibility with debug logging

        // Debug logging - show top results from each method
        print("🔍 [HybridSearch] Final RRF Results (top 5):")
        for (i, result) in finalResults.prefix(5).enumerated() {
            let preview = String(result.metadata.text.prefix(60))
            let tags = result.metadata.tags.joined(separator: ", ")
            let company = result.metadata.customData["company"] ?? "n/a"
            print("🔍 [HybridSearch]   [\(i+1)] RRF=\(String(format: "%.3f", result.score)) [\(company)] [\(tags)] - \(preview)...")
        }

        // Format results
        if finalResults.isEmpty {
            return """
            🔍 Hybrid Memory Search: No relevant memories found

            Query: "\(params.query)"
            \(entities.companies.isEmpty ? "" : "Searched for companies: \(entities.companies.joined(separator: ", "))")

            Try rephrasing your query or check if the information exists.
            """
        }

        var output = "🧠 Hybrid Memory Search Results (\(finalResults.count) found)\n\n"
        output += "Query: \"\(params.query)\"\n"
        if !entities.companies.isEmpty {
            output += "🏢 Companies detected: \(entities.companies.joined(separator: ", "))\n"
        }
        output += "🔬 Method: Keyword (TF-IDF) + Semantic (Vector) + RRF Fusion\n\n"

        for (index, result) in finalResults.enumerated() {
            let rrfScore = Int(result.score * 100)
            let timeAgo = formatTimeAgo(from: result.metadata.timestamp)

            output += "[\(index + 1)] [RRF: \(rrfScore)] \(timeAgo)\n"
            output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            output += "\(result.metadata.text)\n"

            if let company = result.metadata.customData["company"] {
                output += "\n🏢 Company: \(company)\n"
            }
            if !result.metadata.tags.isEmpty {
                output += "🏷️  Tags: \(result.metadata.tags.joined(separator: ", "))\n"
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
