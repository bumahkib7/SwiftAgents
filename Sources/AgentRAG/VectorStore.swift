// AgentRAG/VectorStore.swift
// Protocol for vector database operations (semantic search, RAG)
// Enables persistent memory for agents

import Foundation

/// Metadata associated with a vector
public struct VectorMetadata: Sendable, Codable {
    public let id: String
    public let text: String  // Original text that was embedded
    public let timestamp: Date
    public let tags: [String]
    public let customData: [String: String]  // For app-specific metadata

    public init(
        id: String = UUID().uuidString,
        text: String,
        timestamp: Date = Date(),
        tags: [String] = [],
        customData: [String: String] = [:]
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.tags = tags
        self.customData = customData
    }
}

/// Search result with similarity score
public struct SearchResult: Sendable {
    public let metadata: VectorMetadata
    public let embedding: [Double]
    public let similarity: Double  // Cosine similarity: 0.0 (dissimilar) to 1.0 (identical)

    public init(metadata: VectorMetadata, embedding: [Double], similarity: Double) {
        self.metadata = metadata
        self.embedding = embedding
        self.similarity = similarity
    }
}

/// Protocol for vector database operations
public protocol VectorStore: Sendable {
    /// Insert a vector with metadata
    /// - Parameters:
    ///   - embedding: The vector to store
    ///   - metadata: Associated metadata
    /// - Throws: VectorStoreError if insertion fails
    func insert(embedding: [Double], metadata: VectorMetadata) async throws

    /// Search for similar vectors
    /// - Parameters:
    ///   - embedding: Query vector
    ///   - topK: Number of results to return
    ///   - minSimilarity: Minimum cosine similarity threshold (0.0 to 1.0)
    ///   - filter: Optional filter on metadata
    /// - Returns: Search results sorted by similarity (highest first)
    func search(
        embedding: [Double],
        topK: Int,
        minSimilarity: Double,
        filter: (@Sendable (VectorMetadata) -> Bool)?
    ) async throws -> [SearchResult]

    /// Delete a vector by ID
    func delete(id: String) async throws

    /// Delete all vectors matching a filter
    func deleteAll(where filter: @escaping @Sendable (VectorMetadata) -> Bool) async throws -> Int

    /// Clear all vectors
    func clear() async throws

    /// Get total count of vectors
    func count() async throws -> Int
}

/// Default parameters for convenience
public extension VectorStore {
    func search(
        embedding: [Double],
        topK: Int = 5,
        minSimilarity: Double = 0.0
    ) async throws -> [SearchResult] {
        try await search(
            embedding: embedding,
            topK: topK,
            minSimilarity: minSimilarity,
            filter: nil
        )
    }
}

// MARK: - Errors

public enum VectorStoreError: Error, LocalizedError {
    case invalidDimensions(expected: Int, got: Int)
    case notFound(id: String)
    case databaseError(String)
    case invalidQuery

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions(let expected, let got):
            return "Invalid vector dimensions: expected \(expected), got \(got)"
        case .notFound(let id):
            return "Vector not found: \(id)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .invalidQuery:
            return "Invalid search query"
        }
    }
}

// MARK: - Cosine Similarity Helper

public extension Array where Element == Double {
    /// Calculate cosine similarity between two vectors
    /// Returns value between -1.0 (opposite) and 1.0 (identical)
    func cosineSimilarity(to other: [Double]) -> Double {
        guard count == other.count else { return 0.0 }

        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for i in 0..<count {
            dotProduct += self[i] * other[i]
            normA += self[i] * self[i]
            normB += other[i] * other[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }

        return dotProduct / denominator
    }
}
