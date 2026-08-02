// AgentRAG/AppleNLEmbedder.swift
// Apple NaturalLanguage embeddings provider
// FREE option: Zero dependencies, zero cost, built into macOS/iOS

import Foundation
@preconcurrency import NaturalLanguage  // NLEmbedding is not Sendable
import Logging

@available(macOS 11.0, iOS 14.0, *)
public struct AppleNLEmbedder: EmbeddingProvider {
    private nonisolated(unsafe) let embedding: NLEmbedding  // NLEmbedding is not Sendable
    private let logger: Logger

    public enum Language {
        case english
        case spanish
        case french
        case german
        case italian
        case portuguese

        var nlLanguage: NLLanguage {
            switch self {
            case .english: return .english
            case .spanish: return .spanish
            case .french: return .french
            case .german: return .german
            case .italian: return .italian
            case .portuguese: return .portuguese
            }
        }
    }

    public var modelIdentifier: String {
        "apple-nl-\(embedding.language?.rawValue ?? "unknown")"
    }

    public var dimensions: Int {
        // Apple NLEmbedding uses variable dimensions (typically 128-300)
        // We'll discover this from the first embedding
        return 300  // Typical value for word embeddings
    }

    public init?(
        language: Language = .english,
        logger: Logger = Logger(label: "AppleNLEmbedder")
    ) {
        self.logger = logger

        // Load the embedding model for the specified language
        guard let embedding = NLEmbedding.wordEmbedding(for: language.nlLanguage) else {
            logger.error("Failed to load NLEmbedding for language: \(language.nlLanguage.rawValue)")
            return nil
        }

        self.embedding = embedding
        logger.info("Loaded Apple NLEmbedding for \(language.nlLanguage.rawValue)")
    }

    public func embed(text: String) async throws -> [Double] {
        guard !text.isEmpty else {
            throw EmbeddingError.emptyText
        }

        logger.debug("Embedding text (\(text.count) chars) with Apple NaturalLanguage")

        // NLEmbedding provides word-level embeddings
        // For sentence/document embeddings, we average word vectors
        let tokens = text.split(separator: " ").map(String.init)

        var wordVectors: [[Double]] = []

        for token in tokens {
            if let vector = embedding.vector(for: token.lowercased()) {
                wordVectors.append(vector)
            }
        }

        guard !wordVectors.isEmpty else {
            throw EmbeddingError.invalidResponse
        }

        // Average pooling: mean of all word vectors
        let dimensions = wordVectors[0].count
        var avgVector = [Double](repeating: 0.0, count: dimensions)

        for vector in wordVectors {
            for i in 0..<min(dimensions, vector.count) {
                avgVector[i] += vector[i]
            }
        }

        let count = Double(wordVectors.count)
        avgVector = avgVector.map { $0 / count }

        logger.debug("Embedding generated: \(avgVector.count) dimensions from \(wordVectors.count) words")

        return avgVector
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        // Batch processing for multiple texts
        var embeddings: [[Double]] = []

        for text in texts {
            let embedding = try await embed(text: text)
            embeddings.append(embedding)
        }

        logger.info("Batch embedding complete: \(embeddings.count) vectors")

        return embeddings
    }
}

// MARK: - Sentence Embedding (Alternative Strategy)

@available(macOS 11.0, iOS 14.0, *)
public extension AppleNLEmbedder {
    /// Alternative: Use sentence embedding if available (macOS 12+)
    @available(macOS 12.0, iOS 15.0, *)
    static func sentenceEmbedder(
        language: Language = .english,
        logger: Logger = Logger(label: "AppleNLEmbedder")
    ) -> AppleNLEmbedder? {
        // TODO: Implement sentence embedding support
        // For now, just return word embedding
        return AppleNLEmbedder(language: language, logger: logger)
    }
}
