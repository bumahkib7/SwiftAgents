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

        // Convert tools if present
        let chatTools: [ChatQuery.ChatCompletionToolParam]? = tools.isEmpty ? nil : tools.compactMap { toChatTool($0) }

        // Build query - model is just a string
        let query = ChatQuery(
            messages: chatMessages,
            model: modelName,
            maxCompletionTokens: maxTokens,
            temperature: temperature,
            tools: chatTools
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

        // Convert tools if present
        let chatTools: [ChatQuery.ChatCompletionToolParam]? = tools.isEmpty ? nil : tools.compactMap { toChatTool($0) }

        // Build query - model is just a string
        let query = ChatQuery(
            messages: chatMessages,
            model: modelName,
            maxCompletionTokens: maxTokens,
            temperature: temperature,
            tools: chatTools
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

    private func toChatTool(_ tool: Tool) -> ChatQuery.ChatCompletionToolParam? {
        // Convert [String: Any] to JSONSchema
        guard let schema = convertToJSONSchema(tool.inputSchema) else {
            logger.warning("Failed to convert tool schema: \(tool.name)")
            return nil
        }

        return ChatQuery.ChatCompletionToolParam(
            function: .init(
                name: tool.name,
                description: tool.description,
                parameters: schema
            )
        )
    }

    /// Convert [String: Any] to JSONSchema recursively
    private func convertToJSONSchema(_ dict: [String: Any]) -> JSONSchema? {
        var schemaObject: [String: AnyJSONDocument] = [:]

        for (key, value) in dict {
            guard let doc = convertToJSONDocument(value) else {
                return nil
            }
            schemaObject[key] = doc
        }

        return .object(schemaObject)
    }

    /// Convert Any value to AnyJSONDocument
    private func convertToJSONDocument(_ value: Any) -> AnyJSONDocument? {
        switch value {
        case let intVal as Int:
            return AnyJSONDocument(intVal)
        case let doubleVal as Double:
            return AnyJSONDocument(Decimal(doubleVal))
        case let stringVal as String:
            return AnyJSONDocument(stringVal)
        case let boolVal as Bool:
            return AnyJSONDocument(boolVal)
        case let arrayVal as [Any]:
            let docs = arrayVal.compactMap { convertToJSONDocument($0) }
            guard docs.count == arrayVal.count else { return nil }
            return AnyJSONDocument(docs)
        case let dictVal as [String: Any]:
            var docDict: [String: AnyJSONDocument] = [:]
            for (k, v) in dictVal {
                guard let doc = convertToJSONDocument(v) else { return nil }
                docDict[k] = doc
            }
            return AnyJSONDocument(docDict)
        default:
            logger.warning("Unsupported JSON value type: \(type(of: value))")
            return nil
        }
    }

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
