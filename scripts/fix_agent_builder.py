#!/usr/bin/env python3
"""
Fix AgentBuilder.swift to use correct AgentRunKit types
"""

CORRECT_AGENT_BUILDER = '''// AgentChains/AgentBuilder.swift
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
        public let client: any LLMClient
        public let vectorStore: VectorStore
        public let embedder: EmbeddingProvider
        public let maxIterations: Int
        public let includeMemoryTools: Bool
        public let additionalTools: [any AnyTool<MemoryToolsContext>]
        public let logger: Logger

        public init(
            client: any LLMClient,
            vectorStore: VectorStore,
            embedder: EmbeddingProvider,
            maxIterations: Int = 10,
            includeMemoryTools: Bool = true,
            additionalTools: [any AnyTool<MemoryToolsContext>] = [],
            logger: Logger = Logger(label: "Agent")
        ) {
            self.client = client
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
        var tools: [any AnyTool<MemoryToolsContext>] = []

        // Add memory tools if enabled
        if config.includeMemoryTools {
            tools.append(try createMemorySearchTool())
            tools.append(try createMemoryStoreTool())
            config.logger.info("✓ Memory tools registered (search_memory, store_memory)")
        }

        // Add additional tools
        tools.append(contentsOf: config.additionalTools)

        // Create agent configuration
        var agentConfig = AgentConfiguration()
        agentConfig.maxIterations = config.maxIterations

        // Create agent with AgentRunKit
        let agent = Agent(
            client: config.client,
            tools: tools,
            configuration: agentConfig
        )

        config.logger.info("✅ Agent created with \\(tools.count) tools")

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
        // Create OpenAI client
        let client = OpenAIClient.openAI(
            apiKey: apiKey,
            model: model,
            maxTokens: 8000
        )

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
            client: client,
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
        // Create Anthropic client
        let client = AnthropicClient.anthropic(
            apiKey: apiKey,
            model: model,
            maxTokens: 8000
        )

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
            client: client,
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
        // Create LLM client
        let client: any LLMClient
        switch provider {
        case .openAI:
            client = OpenAIClient.openAI(apiKey: apiKey, model: model, maxTokens: 8000)
        case .anthropic:
            client = AnthropicClient.anthropic(apiKey: apiKey, model: model, maxTokens: 8000)
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
            client: client,
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
'''

from pathlib import Path

def fix_agent_builder():
    """Replace AgentBuilder.swift with corrected version"""
    file_path = Path(__file__).parent.parent / "Sources/AgentChains/AgentBuilder.swift"

    with open(file_path, 'w') as f:
        f.write(CORRECT_AGENT_BUILDER)

    print(f"✅ Fixed: {file_path.name}")
    print("\nChanges:")
    print("  • Agent<MemoryToolsContext> (not Agent<EmptyContext>)")
    print("  • OpenAIClient.openAI() and AnthropicClient.anthropic()")
    print("  • [any AnyTool<MemoryToolsContext>] for tools")
    print("  • AgentConfiguration with maxIterations")

if __name__ == "__main__":
    print("🔧 Fixing AgentBuilder.swift...\n")
    fix_agent_builder()
