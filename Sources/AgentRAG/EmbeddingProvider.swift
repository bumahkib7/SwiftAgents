// AgentRAG/EmbeddingProvider.swift
// Protocol for embedding providers (OpenAI, Apple NaturalLanguage, local models)
// Enables hybrid embedding strategy: remote paid + local free + Apple built-in

import Foundation

/// Protocol for embedding text into vectors
public protocol EmbeddingProvider: Sendable {
    /// The model identifier
    var modelIdentifier: String { get }

    /// The dimensionality of embeddings produced
    var dimensions: Int { get }

    /// Embed a single text into a vector
    /// - Parameter text: The text to embed
    /// - Returns: A vector representation of the text
    func embed(text: String) async throws -> [Double]

    /// Embed multiple texts in a single batch (more efficient)
    /// - Parameter texts: The texts to embed
    /// - Returns: Vector representations for each text
    func embed(texts: [String]) async throws -> [[Double]]
}

/// Default batch implementation (providers can override for efficiency)
public extension EmbeddingProvider {
    func embed(texts: [String]) async throws -> [[Double]] {
        var embeddings: [[Double]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }
        return embeddings
    }
}

// MARK: - Errors

public enum EmbeddingError: Error {
    case emptyText
    case emptyResponse
    case invalidResponse
    case apiError(String)
    case modelNotAvailable
}
