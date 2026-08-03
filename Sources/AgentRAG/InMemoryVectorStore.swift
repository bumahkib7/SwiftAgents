// AgentRAG/InMemoryVectorStore.swift
// Simple in-memory vector store (no external dependencies, async-safe)

import Foundation

/// Simple in-memory vector store for development/testing (non-persistent)
public actor InMemoryVectorStore: VectorStore {
    
    private struct StoredVector {
        let metadata: VectorMetadata
        let embedding: [Double]
    }
    
    private var vectors: [StoredVector] = []
    
    public init() {}
    
    public func insert(embedding: [Double], metadata: VectorMetadata) async throws {
        vectors.append(StoredVector(metadata: metadata, embedding: embedding))
    }
    
    public func search(
        embedding: [Double],
        topK: Int,
        minSimilarity: Double,
        filter: (@Sendable (VectorMetadata) -> Bool)?
    ) async throws -> [SearchResult] {
        var results = vectors.map { stored -> (StoredVector, Double) in
            let similarity = embedding.cosineSimilarity(to: stored.embedding)
            return (stored, similarity)
        }
        
        if let filter = filter {
            results = results.filter { filter($0.0.metadata) }
        }
        
        results = results.filter { $0.1 >= minSimilarity }
        
        return results
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { SearchResult(
                metadata: $0.0.metadata,
                embedding: $0.0.embedding,
                similarity: $0.1
            ) }
    }
    
    public func delete(id: String) async throws {
        vectors.removeAll { $0.metadata.id == id }
    }
    
    public func deleteAll(where filter: @escaping @Sendable (VectorMetadata) -> Bool) async throws -> Int {
        let before = vectors.count
        vectors.removeAll { filter($0.metadata) }
        return before - vectors.count
    }
    
    public func clear() async throws {
        vectors.removeAll()
    }
    
    public func count() async throws -> Int {
        return vectors.count
    }
}
