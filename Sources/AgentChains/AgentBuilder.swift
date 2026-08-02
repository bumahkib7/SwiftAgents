// AgentChains/AgentBuilder.swift
// Builder for creating production agents using AgentRunKit + our VectorStore
// Works on macOS 26 - will migrate to Foundation Models in iOS 27 (September)

import Foundation
import AgentRunKit
import AgentRAG
import AgentTools
import Logging

/// Builder for creating agents with memory capabilities
public struct AgentBuilder {

    /// Configuration for agent creation
    public struct Configuration {
        public let provider: AgentProvider
        public let vectorStore: VectorStore
        public let embedder: EmbeddingProvider
        public let maxIterations: Int
        public let includeMemoryTools: Bool
        public let additionalTools: [AnyTool]
        public let logger: Logger

        public init(
            provider: AgentProvider,
            vectorStore: VectorStore,
            embedder: EmbeddingProvider,
            maxIterations: Int = 10,
            includeMemoryTools: Bool = true,
            additionalTools: [AnyTool] = [],
            logger: Logger = Logger(label: "Agent")
        ) {
            self.provider = provider
            self.vectorStore = vectorStore
            self.embedder = embedder
            self.maxIterations = maxIterations
            self.includeMemoryTools = includeMemoryTools
            self.additionalTools = additionalTools
            self.logger = logger
        }
    }

    /// Create agent with AgentRunKit
    public static func create(config: Configuration) throws -> Agent<MemoryToolsContext> {
        var tools: [AnyTool] = []

        // Add memory tools if enabled
        if config.includeMemoryTools {
            tools.append(try createMemorySearchTool().eraseToAnyTool())
            tools.append(try createMemoryStoreTool().eraseToAnyTool())
            config.logger.info("✓ Memory tools registered (search_memory, store_memory)")
        }

        // Add additional tools
        tools.append(contentsOf: config.additionalTools)

        // Create context
        let context = MemoryToolsContext(
            vectorStore: config.vectorStore,
            embedder: config.embedder
        )

        // Create agent with AgentRunKit
        let agent = Agent(
            provider: config.provider,
            tools: tools,
            context: context,
            maxIterations: config.maxIterations
        )

        config.logger.info("✅ Agent created with \(tools.count) tools")

        return agent
    }

    /// Convenience: Create agent with OpenAI + persistent memory
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - model: Model name (e.g., "gpt-4o")
    ///   - embeddingModel: Embedding model for memory
    ///   - vectorStorePath: Path to SQLite database (nil = in-memory)
    /// - Returns: Configured agent
    public static func createWithOpenAI(
        apiKey: String,
        model: String = "gpt-4o",
        embeddingModel: OpenAIEmbedder.Model = .textEmbedding3Small,
        vectorStorePath: String? = nil
    ) async throws -> Agent<MemoryToolsContext> {
        // Create OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey, model: model)

        // Create embedder
        let embedder = OpenAIEmbedder(
            apiKey: apiKey,
            model: embeddingModel,
            logger: Logger(label: "Embedder")
        )

        // Create vector store
        let vectorStore = try SQLiteVecStore(
            path: vectorStorePath,
            dimensions: embeddingModel.dimensions,
            logger: Logger(label: "VectorStore")
        )

        try await vectorStore.setup()

        let config = Configuration(
            provider: provider,
            vectorStore: vectorStore,
            embedder: embedder,
            logger: Logger(label: "OpenAI-Agent")
        )

        return try create(config: config)
    }

    /// Convenience: Create agent with Anthropic Claude + persistent memory
    /// - Parameters:
    ///   - apiKey: Anthropic API key
    ///   - model: Model name (e.g., "claude-3-5-sonnet-20241022")
    ///   - embeddingModel: OpenAI embedding model (for memory search)
    ///   - openAIKey: OpenAI API key for embeddings
    ///   - vectorStorePath: Path to SQLite database (nil = in-memory)
    /// - Returns: Configured agent
    public static func createWithClaude(
        apiKey: String,
        model: String = "claude-3-5-sonnet-20241022",
        embeddingModel: OpenAIEmbedder.Model = .textEmbedding3Small,
        openAIKey: String,
        vectorStorePath: String? = nil
    ) async throws -> Agent<MemoryToolsContext> {
        // Create Anthropic provider
        let provider = AnthropicProvider(apiKey: apiKey, model: model)

        // Use OpenAI for embeddings
        let embedder = OpenAIEmbedder(
            apiKey: openAIKey,
            model: embeddingModel,
            logger: Logger(label: "Embedder")
        )

        // Create vector store
        let vectorStore = try SQLiteVecStore(
            path: vectorStorePath,
            dimensions: embeddingModel.dimensions,
            logger: Logger(label: "VectorStore")
        )

        try await vectorStore.setup()

        let config = Configuration(
            provider: provider,
            vectorStore: vectorStore,
            embedder: embedder,
            logger: Logger(label: "Claude-Agent")
        )

        return try create(config: config)
    }

    /// Convenience: Create agent with FREE Apple NL embeddings
    /// - Parameters:
    ///   - apiKey: LLM API key (OpenAI or Anthropic)
    ///   - provider: Which LLM provider to use
    ///   - model: Model name
    ///   - language: Apple NL language
    ///   - vectorStorePath: Path to SQLite database (nil = in-memory)
    /// - Returns: Configured agent
    @available(macOS 12.0, iOS 15.0, *)
    public static func createWithAppleNL(
        apiKey: String,
        provider: LLMProvider = .openAI,
        model: String = "gpt-4o",
        language: AppleNLEmbedder.Language = .english,
        vectorStorePath: String? = nil
    ) async throws -> Agent<MemoryToolsContext> {
        // Create LLM provider
        let llmProvider: AgentProvider
        switch provider {
        case .openAI:
            llmProvider = OpenAIProvider(apiKey: apiKey, model: model)
        case .anthropic:
            llmProvider = AnthropicProvider(apiKey: apiKey, model: model)
        }

        // Create FREE Apple NL embedder
        guard let embedder = AppleNLEmbedder.sentenceEmbedder(
            language: language,
            logger: Logger(label: "AppleNL")
        ) else {
            throw AgentBuilderError.embeddingInitFailed
        }

        // Create vector store
        let vectorStore = try SQLiteVecStore(
            path: vectorStorePath,
            dimensions: embedder.dimensions,
            logger: Logger(label: "VectorStore")
        )

        try await vectorStore.setup()

        let config = Configuration(
            provider: llmProvider,
            vectorStore: vectorStore,
            embedder: embedder,
            logger: Logger(label: "AppleNL-Agent")
        )

        return try create(config: config)
    }
}

// MARK: - LLM Provider Enum

public enum LLMProvider {
    case openAI
    case anthropic
}

// MARK: - Errors

public enum AgentBuilderError: Error, LocalizedError {
    case embeddingInitFailed

    public var errorDescription: String? {
        switch self {
        case .embeddingInitFailed:
            return "Failed to initialize Apple NL embedding model"
        }
    }
}
