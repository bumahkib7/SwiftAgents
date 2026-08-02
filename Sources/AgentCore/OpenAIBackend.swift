// AgentCore/OpenAIBackend.swift
// OpenAI GPT-4 API backend implementation
// Thin wrapper around MacPaw/OpenAI library

import Foundation
import Logging
import OpenAI

@available(iOS 13.0.0, *)
public struct OpenAIBackend: LanguageModelBackend {
    private let client: OpenAI
    private let modelName: String
    private let logger: Logger

    public init(apiKey: String, model: String = "gpt-4o", logger: Logger = Logger(label: "OpenAIBackend")) {
        self.client = OpenAI(apiToken: apiKey)
        self.modelName = model
        self.logger = logger
    }

    public func generate(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool
    ) async throws -> AgentResponse {

        logger.info("Calling OpenAI API: model=\(modelName), tokens=\(maxTokens), tools=\(tools.count)")

        // Convert our messages to OpenAI format
        let chatMessages = messages.map { toChatMessage($0) }

        // TODO: Add tool support (requires JSONSchema conversion)
        // For now, ignore tools parameter

        // Build query - model is just a string
        let query = ChatQuery(
            messages: chatMessages,
            model: modelName,
            maxCompletionTokens: maxTokens,
            temperature: temperature
        )

        // Call OpenAI API
        let result = try await client.chats(query: query)

        return try parseResponse(result)
    }

    public func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse {

        logger.info("Streaming from OpenAI API: model=\(modelName), tokens=\(maxTokens)")

        // Convert our messages to OpenAI format
        let chatMessages = messages.map { toChatMessage($0) }

        // TODO: Add tool support (requires JSONSchema conversion)
        // For now, ignore tools parameter

        // Build query - model is just a string
        let query = ChatQuery(
            messages: chatMessages,
            model: modelName,
            maxCompletionTokens: maxTokens,
            temperature: temperature
        )

        // Stream chunks
        var accumulatedText = ""
        var inputTokens = 0
        var outputTokens = 0
        var stopReason: AgentResponse.StopReason = .endTurn

        let stream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)

        for try await chunk in stream {
            if let choice = chunk.choices.first {
                // Accumulate text deltas
                if let delta = choice.delta.content {
                    accumulatedText += delta
                    await onChunk(delta)
                }

                // Check for stop reason
                if let finishReason = choice.finishReason {
                    stopReason = parseFinishReason(finishReason.rawValue)
                }
            }

            // Track token usage if provided
            if let usage = chunk.usage {
                inputTokens = usage.promptTokens
                outputTokens = usage.completionTokens
            }
        }

        let message = AgentMessage(
            role: .assistant,
            content: accumulatedText,
            toolCalls: nil
        )

        logger.info("Stream completed: \(accumulatedText.count) chars, \(inputTokens) + \(outputTokens) tokens")

        return AgentResponse(
            message: message,
            stopReason: stopReason,
            usage: AgentResponse.Usage(inputTokens: inputTokens, outputTokens: outputTokens),
            cacheStats: nil  // OpenAI doesn't support prompt caching yet
        )
    }

    // MARK: - Helpers

    private func toChatMessage(_ message: AgentMessage) -> ChatQuery.ChatCompletionMessageParam {
        // Use convenience initializer that accepts role and content string
        return ChatQuery.ChatCompletionMessageParam(
            role: message.role == .system ? .system : (message.role == .user ? .user : .assistant),
            content: message.content
        )!  // Force unwrap is safe - we always provide content
    }

    // TODO: Add tool support
    // Need to convert [String: Any] to JSONSchema
    // private func toChatTool(_ tool: Tool) -> ChatQuery.ChatCompletionToolParam { ... }

    private func parseResponse(_ result: ChatResult) throws -> AgentResponse {
        guard let choice = result.choices.first else {
            throw OpenAIBackendError.emptyResponse
        }

        let content = choice.message.content ?? ""
        let stopReason = parseFinishReason(choice.finishReason)

        // Parse tool calls if present
        var toolCalls: [ToolCall]? = nil
        if let openAIToolCalls = choice.message.toolCalls {
            toolCalls = openAIToolCalls.compactMap { call in
                guard let args = try? JSONSerialization.jsonObject(with: Data(call.function.arguments.utf8)) as? [String: Any] else {
                    return nil
                }
                return ToolCall(id: call.id, name: call.function.name, arguments: args)
            }
        }

        let message = AgentMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls
        )

        let usage = AgentResponse.Usage(
            inputTokens: result.usage?.promptTokens ?? 0,
            outputTokens: result.usage?.completionTokens ?? 0
        )

        logger.info("Response generated: \(usage.outputTokens) tokens, stop reason: \(stopReason)")

        return AgentResponse(
            message: message,
            stopReason: stopReason,
            usage: usage,
            cacheStats: nil  // OpenAI doesn't support prompt caching
        )
    }

    private func parseFinishReason(_ reason: String?) -> AgentResponse.StopReason {
        switch reason {
        case "stop": return .endTurn
        case "length": return .maxTokens
        case "tool_calls": return .toolUse
        case "content_filter": return .stopSequence
        default: return .endTurn
        }
    }
}

// MARK: - Errors

public enum OpenAIBackendError: Error {
    case emptyResponse
}
