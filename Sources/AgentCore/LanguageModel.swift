// AgentCore/LanguageModel.swift
// Protocol that wraps any LLM backend (Anthropic API, OpenAI, local models, Apple's LanguageModel when available)
// Absorbs beta API churn in one place

import Foundation
import Logging

// MARK: - Core Protocols

/// A message in a conversation
public struct AgentMessage: Sendable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
    }

    public struct CacheControl: Sendable, Codable {
        public let type: String  // "ephemeral"

        public init(type: String = "ephemeral") {
            self.type = type
        }
    }

    public let role: Role
    public let content: String
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let cacheControl: CacheControl?  // For prompt caching (90% cost reduction!)

    public init(role: Role, content: String, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil, cacheControl: CacheControl? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.cacheControl = cacheControl
    }
}

/// Wrapper for JSON data that's unchecked Sendable
private struct JSONValue: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}

/// A tool call request from the model
public struct ToolCall: Sendable, Codable {
    public let id: String
    public let name: String
    private let _arguments: JSONValue

    public var arguments: [String: Any] {
        _arguments.value
    }

    enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }

    public init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self._arguments = JSONValue(arguments)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Decode JSON object as [String: Any]
        let jsonData = try container.decode(Data.self, forKey: .arguments)
        let anyDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        _arguments = JSONValue(anyDict)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)

        let jsonData = try JSONSerialization.data(withJSONObject: _arguments.value)
        try container.encode(jsonData, forKey: .arguments)
    }
}

/// Tool definition for the model
public struct Tool: Sendable {
    public let name: String
    public let description: String
    private let _inputSchema: JSONValue

    public var inputSchema: [String: Any] {
        _inputSchema.value
    }

    public init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self._inputSchema = JSONValue(inputSchema)
    }
}

/// Response from the language model
public struct AgentResponse: Sendable {
    public let message: AgentMessage
    public let stopReason: StopReason
    public let usage: Usage

    public enum StopReason: Sendable {
        case endTurn
        case maxTokens
        case toolUse
        case stopSequence
    }

    public struct Usage: Sendable {
        public let inputTokens: Int
        public let outputTokens: Int

        public init(inputTokens: Int, outputTokens: Int) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public init(message: AgentMessage, stopReason: StopReason, usage: Usage) {
        self.message = message
        self.stopReason = stopReason
        self.usage = usage
    }
}

// MARK: - Language Model Protocol

/// Backend-agnostic language model interface
public protocol LanguageModelBackend: Sendable {
    /// Generate a response given a conversation history
    func generate(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool
    ) async throws -> AgentResponse

    /// Stream a response (optional, falls back to generate)
    func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse
}

// MARK: - Default Stream Implementation

public extension LanguageModelBackend {
    func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse {
        // Default: just call generate and return full response
        let response = try await generate(
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature,
            extendedThinking: extendedThinking
        )
        await onChunk(response.message.content)
        return response
    }
}

// MARK: - Session Management

/// Manages a stateful conversation with a language model
@MainActor
public final class LanguageModelSession {
    private let backend: LanguageModelBackend
    private var messages: [AgentMessage] = []
    private let logger: Logger

    public var conversationHistory: [AgentMessage] {
        messages
    }

    public init(backend: LanguageModelBackend, logger: Logger = Logger(label: "AgentCore")) {
        self.backend = backend
        self.logger = logger
    }

    /// Add a message to the conversation history
    public func addMessage(_ message: AgentMessage) {
        messages.append(message)
    }

    /// Generate a response and add it to history
    public func generate(
        prompt: String,
        tools: [Tool] = [],
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        extendedThinking: Bool = false
    ) async throws -> AgentResponse {
        let userMessage = AgentMessage(role: .user, content: prompt)
        messages.append(userMessage)

        logger.info("Generating response for prompt (\(prompt.count) chars) with \(tools.count) tools")

        let response = try await backend.generate(
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature,
            extendedThinking: extendedThinking
        )

        messages.append(response.message)

        logger.info("Response generated: \(response.usage.outputTokens) tokens, stop reason: \(response.stopReason)")

        return response
    }

    /// Stream a response
    public func stream(
        prompt: String,
        tools: [Tool] = [],
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        extendedThinking: Bool = false,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> AgentResponse {
        let userMessage = AgentMessage(role: .user, content: prompt)
        messages.append(userMessage)

        let response = try await backend.stream(
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature,
            extendedThinking: extendedThinking,
            onChunk: onChunk
        )

        messages.append(response.message)
        return response
    }

    /// Stream with direct message control (for prompt caching)
    public func streamWithMessages(
        _ newMessages: [AgentMessage],
        tools: [Tool] = [],
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        extendedThinking: Bool = false,
        onChunk: @Sendable @escaping (String) async -> Void
    ) async throws -> AgentResponse {
        let allMessages = messages + newMessages

        let response = try await backend.stream(
            messages: allMessages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature,
            extendedThinking: extendedThinking,
            onChunk: onChunk
        )

        messages.append(contentsOf: newMessages)
        messages.append(response.message)
        return response
    }

    /// Clear conversation history
    public func reset() {
        messages.removeAll()
        logger.info("Session reset")
    }
}
