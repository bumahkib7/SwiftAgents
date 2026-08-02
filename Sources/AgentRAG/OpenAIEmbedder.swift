// AgentRAG/OpenAIEmbedder.swift
// OpenAI embeddings provider using MacPaw/OpenAI library
// Production option: High quality, paid ($0.02 per 1M tokens for text-embedding-3-small)

import Foundation
import Logging
import OpenAI

public struct OpenAIEmbedder: EmbeddingProvider {
    private let client: OpenAI
    private let model: Model
    private let logger: Logger

    public enum Model: String, Sendable {
        case textEmbedding3Small = "text-embedding-3-small"  // 1536 dims, $0.02/1M tokens
        case textEmbedding3Large = "text-embedding-3-large"  // 3072 dims, $0.13/1M tokens
        case textEmbeddingAda002 = "text-embedding-ada-002"  // 1536 dims, legacy

        public var dimensions: Int {
            switch self {
            case .textEmbedding3Small, .textEmbeddingAda002:
                return 1536
            case .textEmbedding3Large:
                return 3072
            }
        }
    }

    public var modelIdentifier: String {
        model.rawValue
    }

    public var dimensions: Int {
        model.dimensions
    }

    public init(
        apiKey: String,
        model: Model = .textEmbedding3Small,
        logger: Logger = Logger(label: "OpenAIEmbedder")
    ) {
        self.client = OpenAI(apiToken: apiKey)
        self.model = model
        self.logger = logger
    }

    public func embed(text: String) async throws -> [Double] {
        guard !text.isEmpty else {
            throw EmbeddingError.emptyText
        }

        logger.info("Embedding text (\(text.count) chars) with \(model.rawValue)")

        let query = EmbeddingsQuery(
            input: .string(text),
            model: model.rawValue  // Model is just a string
        )

        let result = try await client.embeddings(query: query)

        guard let embedding = result.data.first?.embedding else {
            throw EmbeddingError.emptyResponse
        }

        logger.info("Embedding generated: \(embedding.count) dimensions, \(result.usage.totalTokens) tokens")

        return embedding
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        guard !texts.isEmpty else {
            return []
        }

        // Filter out empty strings
        let validTexts = texts.filter { !$0.isEmpty }
        guard !validTexts.isEmpty else {
            throw EmbeddingError.emptyText
        }

        logger.info("Batch embedding \(validTexts.count) texts with \(model.rawValue)")

        let query = EmbeddingsQuery(
            input: .stringList(validTexts),
            model: model.rawValue  // Model is just a string
        )

        let result = try await client.embeddings(query: query)

        let embeddings = result.data.map { $0.embedding }

        logger.info("Batch embedding complete: \(embeddings.count) vectors, \(result.usage.totalTokens) tokens")

        return embeddings
    }
}
