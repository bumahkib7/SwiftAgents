// AgentTools/MemoryStoreTool.swift
// Memory storage tool for persisting information in VectorStore
// Enables agents to autonomously remember important information

import Foundation
import AgentCore
import AgentRAG

/// Tool for storing information in long-term memory
/// The agent uses this to remember important facts, preferences, or context
public struct MemoryStoreTool: AgentTool {
    public let name = "store_memory"
    public let description = """
    Store important information in your long-term memory for future reference.

    Use this when:
    - The user shares important preferences or information
    - You learn something that will be useful later
    - You need to remember context across conversations
    - You want to build a knowledge base about the user or project

    Examples of what to store:
    - "User prefers React over Vue for frontend development"
    - "The authentication system uses JWT tokens with 24h expiry"
    - "Customer support hours are 9am-5pm EST Monday-Friday"

    The information will be embedded using AI and stored with semantic search,
    so you can find it later even if you search with different words.

    Parameters:
    - information: What you want to remember (be specific and clear)
    - tags: Categories for this memory (e.g., ["user_preference", "technical"])
    - importance: How important this is (1-10, default: 5)
    """

    private let _inputSchema = SchemaWrapper([
        "type": "object",
        "properties": [
            "information": [
                "type": "string",
                "description": "The information to store - be specific and self-contained"
            ],
            "tags": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Categories for this memory (e.g., ['user_preference', 'technical', 'business'])"
            ],
            "importance": [
                "type": "integer",
                "description": "Importance level 1-10 (1=trivial, 10=critical)",
                "default": 5
            ]
        ],
        "required": ["information", "tags"]
    ])

    public var inputSchema: [String: Any] {
        _inputSchema.value
    }

    private let vectorStore: VectorStore
    private let embedder: EmbeddingProvider

    public init(vectorStore: VectorStore, embedder: EmbeddingProvider) {
        self.vectorStore = vectorStore
        self.embedder = embedder
    }

    public func execute(parameters: [String: Any]) async throws -> String {
        guard let information = parameters["information"] as? String else {
            throw ToolError.invalidParameters("'information' parameter is required")
        }

        guard let tags = parameters["tags"] as? [String] else {
            throw ToolError.invalidParameters("'tags' parameter is required")
        }

        let importance = parameters["importance"] as? Int ?? 5

        // Validate parameters
        guard !information.isEmpty else {
            throw ToolError.invalidParameters("information cannot be empty")
        }

        guard !tags.isEmpty else {
            throw ToolError.invalidParameters("at least one tag is required")
        }

        guard importance >= 1 && importance <= 10 else {
            throw ToolError.invalidParameters("importance must be between 1 and 10")
        }

        // Generate embedding for the information
        let embedding = try await embedder.embed(text: information)

        // Create metadata
        let metadata = VectorMetadata(
            text: information,
            timestamp: Date(),
            tags: tags,
            customData: [
                "importance": String(importance),
                "stored_at": ISO8601DateFormatter().string(from: Date())
            ]
        )

        // Store in vector database
        try await vectorStore.insert(embedding: embedding, metadata: metadata)

        // Format confirmation
        return """
        💾 Memory Stored Successfully

        Information: "\(information)"
        Tags: \(tags.joined(separator: ", "))
        Importance: \(importance)/10
        ID: \(metadata.id)

        This information has been embedded and stored in your long-term memory.
        You can search for it later using the search_memory tool, even with
        different words or phrasing.
        """
    }
}

// MARK: - JSON Schema Wrapper

private struct SchemaWrapper: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) {
        self.value = value
    }
}
