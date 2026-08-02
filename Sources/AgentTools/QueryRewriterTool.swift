// AgentTools/QueryRewriterTool.swift
// Query rewriting tool using LLM for better retrieval
// Automatically improves user queries for semantic search

import Foundation
import AgentCore

/// Tool that rewrites queries to improve search results
/// The agent uses this to optimize vague or ambiguous queries before searching
public struct QueryRewriterTool: AgentTool {
    public let name = "rewrite_query"
    public let description = """
    Rewrite a user query to make it more effective for semantic search.

    Use this when:
    - The user's question is vague or ambiguous
    - You need to expand abbreviations or acronyms
    - The query could benefit from additional context
    - You want to make implicit information explicit

    Examples:
    - "auth" → "user authentication and login system"
    - "API slow" → "API performance issues and optimization"
    - "React bug" → "React component rendering bugs and errors"

    This tool uses AI to expand and clarify queries while preserving intent.

    Parameters:
    - original_query: The original user query to rewrite
    - context: Optional additional context about what you're looking for
    """

    private let _inputSchema = SchemaWrapper([
        "type": "object",
        "properties": [
            "original_query": [
                "type": "string",
                "description": "The original query that needs improvement"
            ],
            "context": [
                "type": "string",
                "description": "Optional: Additional context about the search intent"
            ]
        ],
        "required": ["original_query"]
    ])

    public var inputSchema: [String: Any] {
        _inputSchema.value
    }

    private let backend: LanguageModelBackend

    public init(backend: LanguageModelBackend) {
        self.backend = backend
    }

    public func execute(parameters: [String: Any]) async throws -> String {
        guard let originalQuery = parameters["original_query"] as? String else {
            throw ToolError.invalidParameters("'original_query' parameter is required")
        }

        let context = parameters["context"] as? String

        // Build system prompt for query rewriting
        let systemPrompt = """
        You are a query optimization expert. Your job is to rewrite search queries to be:
        1. More specific and descriptive
        2. Expanded with relevant synonyms and related terms
        3. Clear about the intent
        4. Better suited for semantic similarity search

        Rules:
        - Expand abbreviations (e.g., "auth" → "authentication")
        - Add relevant context (e.g., "login" → "user login and authentication")
        - Keep technical terms accurate
        - Don't change the fundamental intent
        - Return ONLY the rewritten query, no explanation

        Examples:
        Input: "auth"
        Output: user authentication login security

        Input: "API slow"
        Output: API performance optimization response time latency

        Input: "React component not updating"
        Output: React component state update rendering lifecycle hooks
        """

        var userPrompt = "Rewrite this query: \(originalQuery)"
        if let context = context {
            userPrompt += "\n\nContext: \(context)"
        }

        let messages = [
            AgentMessage(role: .system, content: systemPrompt),
            AgentMessage(role: .user, content: userPrompt)
        ]

        // Generate rewritten query
        let response = try await backend.generate(
            messages: messages,
            tools: [],
            maxTokens: 200,
            temperature: 0.3,  // Lower temperature for consistency
            extendedThinking: false
        )

        let rewrittenQuery = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        ✏️ Query Rewrite

        Original: "\(originalQuery)"
        Rewritten: "\(rewrittenQuery)"

        This expanded query should improve search results by:
        - Adding relevant synonyms and related terms
        - Making implicit information explicit
        - Expanding abbreviations and technical shorthand
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
