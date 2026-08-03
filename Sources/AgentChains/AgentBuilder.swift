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
        public let client: any LLMClient
        public let vectorStore: VectorStore
        public let embedder: EmbeddingProvider
        public let maxIterations: Int
        public let includeMemoryTools: Bool
        public let includeFileSystemTools: Bool
        public let includeBashTool: Bool
        public let includeCodeExecutor: Bool
        public let includeWebTools: Bool
        public let includeSearchTools: Bool
        public let includeGitTools: Bool
        public let includeEditTools: Bool
        public let includeWebSearch: Bool
        public let additionalTools: [any AnyTool<MemoryToolsContext>]
        public let logger: Logger

        public init(
            client: any LLMClient,
            vectorStore: VectorStore,
            embedder: EmbeddingProvider,
            maxIterations: Int = 10,
            includeMemoryTools: Bool = true,
            includeFileSystemTools: Bool = true,
            includeBashTool: Bool = true,
            includeCodeExecutor: Bool = true,
            includeWebTools: Bool = true,
            includeSearchTools: Bool = true,
            includeGitTools: Bool = true,
            includeEditTools: Bool = true,
            includeWebSearch: Bool = true,
            additionalTools: [any AnyTool<MemoryToolsContext>] = [],
            logger: Logger = Logger(label: "Agent")
        ) {
            self.client = client
            self.vectorStore = vectorStore
            self.embedder = embedder
            self.maxIterations = maxIterations
            self.includeMemoryTools = includeMemoryTools
            self.includeFileSystemTools = includeFileSystemTools
            self.includeBashTool = includeBashTool
            self.includeCodeExecutor = includeCodeExecutor
            self.includeWebTools = includeWebTools
            self.includeSearchTools = includeSearchTools
            self.includeGitTools = includeGitTools
            self.includeEditTools = includeEditTools
            self.includeWebSearch = includeWebSearch
            self.additionalTools = additionalTools
            self.logger = logger
        }
    }

    /// Create agent with AgentRunKit
    @available(iOS 16.0.0, *)
    public static func create(config: Configuration) throws -> Agent<MemoryToolsContext> {
        var tools: [any AnyTool<MemoryToolsContext>] = []

        // Add memory tools if enabled
        if config.includeMemoryTools {
            tools.append(try createMemorySearchTool())
            tools.append(try createMemoryStoreTool())
            config.logger.info("✓ Memory tools registered (search_memory, store_memory)")
        }

        // Add file system tools if enabled
        if config.includeFileSystemTools {
            tools.append(try createFileReadTool())
            tools.append(try createFileWriteTool())
            tools.append(try createListDirectoryTool())
            tools.append(try createFileDeleteTool())
            config.logger.info("✓ File system tools registered (read_file, write_file, list_directory, delete_file)")
        }

        // Add bash tool if enabled
        if config.includeBashTool {
            tools.append(try createBashTool())
            config.logger.info("✓ Bash tool registered (bash)")
        }

        // Add code executor if enabled
        if config.includeCodeExecutor {
            tools.append(try createCodeExecutorTool())
            config.logger.info("✓ Code executor registered (execute_code)")
        }

        // Add web tools if enabled
        if config.includeWebTools {
            tools.append(try createWebFetchTool())
            tools.append(try createHttpRequestTool())
            config.logger.info("✓ Web tools registered (fetch_url, http_request)")
        }

        // Add search tools if enabled
        if config.includeSearchTools {
            tools.append(try createGrepTool())
            tools.append(try createGlobTool())
            tools.append(try createFindTool())
            config.logger.info("✓ Search tools registered (grep, glob, find)")
        }

        // Add git tools if enabled
        if config.includeGitTools {
            tools.append(try createGitStatusTool())
            tools.append(try createGitDiffTool())
            tools.append(try createGitCommitTool())
            tools.append(try createGitLogTool())
            tools.append(try createGitBranchTool())
            tools.append(try createGitCloneTool())
            config.logger.info("✓ Git tools registered (git_status, git_diff, git_commit, git_log, git_branch, git_clone)")
        }

        // Add edit tools if enabled
        if config.includeEditTools {
            tools.append(try createEditTool())
            tools.append(try createMultiEditTool())
            config.logger.info("✓ Edit tools registered (edit_file, edit_files)")
        }

        // Add web search if enabled
        if config.includeWebSearch {
            tools.append(try createWebSearchTool())
            config.logger.info("✓ Web search registered (web_search)")
        }

        // Add additional tools
        tools.append(contentsOf: config.additionalTools)

        // Create agent configuration
        let agentConfig = AgentConfiguration(maxIterations: config.maxIterations)

        // Create agent with AgentRunKit
        let agent = Agent(
            client: config.client,
            tools: tools,
            configuration: agentConfig
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

        // Create vector store (using InMemoryVectorStore - SQLiteVec has macOS compatibility issues)
        let vectorStore = InMemoryVectorStore()

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
        let client = try AnthropicClient(
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

        // Create vector store (using InMemoryVectorStore - SQLiteVec has macOS compatibility issues)
        let vectorStore = InMemoryVectorStore()

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
            client = try AnthropicClient(apiKey: apiKey, model: model, maxTokens: 8000)
        }

        // Create FREE Apple NL embedder
        guard let embedder = AppleNLEmbedder.sentenceEmbedder(
            language: language,
            logger: Logger(label: "AppleNL")
        ) else {
            throw AgentBuilderError.embeddingInitFailed
        }

        // Create vector store (using InMemoryVectorStore - SQLiteVec has macOS compatibility issues)
        let vectorStore = InMemoryVectorStore()

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
