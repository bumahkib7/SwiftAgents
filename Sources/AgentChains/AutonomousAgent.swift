// AgentChains/AutonomousAgent.swift
// Autonomous agent with built-in memory and query rewriting
// "LangChain for Swift" - agents that use tools automatically

import Foundation
import AgentCore
import AgentRAG
import AgentTools
import Logging

/// Factory for creating autonomous agents with memory capabilities
/// These agents automatically use tools for memory search, query rewriting, and storage
@MainActor
public struct AutonomousAgent {

    /// Configuration for autonomous agent behavior
    public struct Configuration {
        public let backend: LanguageModelBackend
        public let vectorStore: VectorStore
        public let embedder: EmbeddingProvider
        public let maxIterations: Int
        public let includeMemoryTools: Bool
        public let includeQueryRewriter: Bool
        public let additionalTools: [AgentTool]
        public let logger: Logger

        public init(
            backend: LanguageModelBackend,
            vectorStore: VectorStore,
            embedder: EmbeddingProvider,
            maxIterations: Int = 10,
            includeMemoryTools: Bool = true,
            includeQueryRewriter: Bool = true,
            additionalTools: [AgentTool] = [],
            logger: Logger = Logger(label: "AutonomousAgent")
        ) {
            self.backend = backend
            self.vectorStore = vectorStore
            self.embedder = embedder
            self.maxIterations = maxIterations
            self.includeMemoryTools = includeMemoryTools
            self.includeQueryRewriter = includeQueryRewriter
            self.additionalTools = additionalTools
            self.logger = logger
        }
    }

    /// Create an autonomous agent with automatic memory and tool usage
    /// - Parameter config: Agent configuration
    /// - Returns: Configured ReActAgent ready to use
    public static func create(config: Configuration) -> ReActAgent {
        let session = LanguageModelSession(backend: config.backend)
        let registry = ToolRegistry(logger: config.logger)

        // Add memory tools if enabled
        if config.includeMemoryTools {
            registry.register(MemorySearchTool(
                vectorStore: config.vectorStore,
                embedder: config.embedder
            ))

            registry.register(MemoryStoreTool(
                vectorStore: config.vectorStore,
                embedder: config.embedder
            ))

            config.logger.info("✓ Memory tools registered (search_memory, store_memory)")
        }

        // Add query rewriter if enabled
        if config.includeQueryRewriter {
            registry.register(QueryRewriterTool(backend: config.backend))
            config.logger.info("✓ Query rewriter registered (rewrite_query)")
        }

        // Add additional tools
        for tool in config.additionalTools {
            registry.register(tool)
            config.logger.info("✓ Custom tool registered: \(tool.name)")
        }

        return ReActAgent(
            session: session,
            toolRegistry: registry,
            maxIterations: config.maxIterations,
            logger: config.logger
        )
    }

    /// Convenience method: Create agent with OpenAI + persistent memory
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - model: GPT model to use (default: gpt-4o)
    ///   - embeddingModel: Embedding model (default: text-embedding-3-small)
    ///   - vectorStorePath: Path to SQLite vector database (nil = in-memory)
    ///   - dimensions: Vector dimensions (must match embedding model)
    ///   - additionalTools: Additional tools to register
    /// - Returns: Configured autonomous agent
    @available(iOS 13.0.0, *)
    public static func createWithOpenAI(
        apiKey: String,
        model: String = "gpt-4o",
        embeddingModel: OpenAIEmbedder.Model = .textEmbedding3Small,
        vectorStorePath: String? = nil,
        additionalTools: [AgentTool] = []
    ) throws -> ReActAgent {
        // Create OpenAI backend
        let backend = OpenAIBackend(
            apiKey: apiKey,
            model: model,
            logger: Logger(label: "OpenAI")
        )

        // Create OpenAI embedder
        let embedder = OpenAIEmbedder(
            apiKey: apiKey,
            model: embeddingModel,
            logger: Logger(label: "OpenAIEmbedder")
        )

        // Create vector store
        let vectorStore = try SQLiteVecStore(
            path: vectorStorePath,
            dimensions: embeddingModel.dimensions,
            logger: Logger(label: "VectorStore")
        )

        // Initialize tables
        Task {
            try await vectorStore.setup()
        }

        let config = Configuration(
            backend: backend,
            vectorStore: vectorStore,
            embedder: embedder,
            includeMemoryTools: true,
            includeQueryRewriter: true,
            additionalTools: additionalTools,
            logger: Logger(label: "AutonomousAgent")
        )

        return create(config: config)
    }

    /// Convenience method: Create agent with Apple NL (FREE) + persistent memory
    /// - Parameters:
    ///   - apiKey: OpenAI API key (for LLM only, embeddings are FREE)
    ///   - model: GPT model to use (default: gpt-4o)
    ///   - language: Apple NL language (default: English)
    ///   - vectorStorePath: Path to SQLite vector database (nil = in-memory)
    ///   - additionalTools: Additional tools to register
    /// - Returns: Configured autonomous agent
    @available(macOS 12.0, iOS 15.0, *)
    public static func createWithAppleNL(
        apiKey: String,
        model: String = "gpt-4o",
        language: AppleNLEmbedder.Language = .english,
        vectorStorePath: String? = nil,
        additionalTools: [AgentTool] = []
    ) throws -> ReActAgent {
        // Create OpenAI backend for LLM
        let backend = OpenAIBackend(
            apiKey: apiKey,
            model: model,
            logger: Logger(label: "OpenAI")
        )

        // Create Apple NL embedder (FREE!)
        guard let embedder = AppleNLEmbedder.sentenceEmbedder(
            language: language,
            logger: Logger(label: "AppleNLEmbedder")
        ) else {
            throw AutonomousAgentError.embeddingInitFailed
        }

        // Create vector store
        let vectorStore = try SQLiteVecStore(
            path: vectorStorePath,
            dimensions: embedder.dimensions,
            logger: Logger(label: "VectorStore")
        )

        // Initialize tables
        Task {
            try await vectorStore.setup()
        }

        let config = Configuration(
            backend: backend,
            vectorStore: vectorStore,
            embedder: embedder,
            includeMemoryTools: true,
            includeQueryRewriter: true,
            additionalTools: additionalTools,
            logger: Logger(label: "AutonomousAgent")
        )

        return create(config: config)
    }
}

// MARK: - Errors

public enum AutonomousAgentError: Error, LocalizedError {
    case embeddingInitFailed

    public var errorDescription: String? {
        switch self {
        case .embeddingInitFailed:
            return "Failed to initialize embedding model"
        }
    }
}
