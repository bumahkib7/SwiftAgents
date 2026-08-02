// AgentCore/AnthropicBackend.swift
// Anthropic Claude API backend implementation
// Supports extended thinking mode, tool use, streaming

import Foundation
import Logging

@available(iOS 13.0.0, *)
public struct AnthropicBackend: LanguageModelBackend {
    private let apiKey: String
    private let model: String
    private let logger: Logger

    public init(apiKey: String, model: String = "claude-opus-5", logger: Logger = Logger(label: "AnthropicBackend")) {
        self.apiKey = apiKey
        self.model = model
        self.logger = logger
    }

    public func generate(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool
    ) async throws -> AgentResponse {

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")  // Current stable version (2026)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.addValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")  // Enable caching

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { messageToDict($0) }
        ]

        // Temperature is deprecated for newer Claude models (Opus 5, etc.)
        // Only include it for older models if needed
        // For now, omit temperature to support latest models

        // Extended thinking is built into the model itself (claude-sonnet-4.6, etc.)
        // Not a request parameter - remove the invalid parameter

        if !tools.isEmpty {
            body["tools"] = tools.map { toolToDict($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Calling Anthropic API: model=\(model), tokens=\(maxTokens), tools=\(tools.count)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error \(httpResponse.statusCode): \(errorBody)")
            throw AnthropicError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        return try parseResponse(json)
    }

    public func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")  // Current stable version (2026)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.addValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")  // Enable caching
        request.timeoutInterval = 120  // 2 minute timeout for streaming

        // Build request body with stream: true
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true  // Enable SSE streaming
        ]

        // Separate system messages from user/assistant messages (required for caching)
        let systemMessages = messages.filter { $0.role == .system }
        let conversationMessages = messages.filter { $0.role != .system }

        // Add system messages with caching support
        if !systemMessages.isEmpty {
            body["system"] = systemMessages.map { message in
                var block: [String: Any] = [
                    "type": "text",
                    "text": message.content
                ]
                if let cacheControl = message.cacheControl {
                    block["cache_control"] = ["type": cacheControl.type]
                }
                return block
            }
        }

        body["messages"] = conversationMessages.map { messageToDict($0) }

        if !tools.isEmpty {
            body["tools"] = tools.map { toolToDict($0) }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Streaming from Anthropic API: model=\(model), tokens=\(maxTokens)")

        // Use URLSession for streaming with timeout
        let session = URLSession.shared

        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        } catch {
            logger.error("Network error during streaming: \(error). Falling back to non-streaming.")
            // FALLBACK: If streaming fails (network error, proxy issues), use regular generate()
            return try await generate(
                messages: messages,
                tools: tools,
                maxTokens: maxTokens,
                temperature: temperature,
                extendedThinking: extendedThinking
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid HTTP response from Anthropic. Falling back.")
            return try await generate(messages: messages, tools: tools, maxTokens: maxTokens, temperature: temperature, extendedThinking: extendedThinking)
        }

        logger.info("HTTP response: status=\(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            logger.error("Streaming failed with status \(httpResponse.statusCode). Falling back.")
            return try await generate(messages: messages, tools: tools, maxTokens: maxTokens, temperature: temperature, extendedThinking: extendedThinking)
        }

        // Parse SSE stream
        var accumulatedText = ""
        var stopReason: AgentResponse.StopReason = .endTurn
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationTokens = 0
        var cacheReadTokens = 0
        var linesProcessed = 0

        logger.info("Starting SSE stream parsing...")

        for try await line in asyncBytes.lines {
            linesProcessed += 1
            if linesProcessed % 10 == 0 {
                logger.debug("Processed \(linesProcessed) SSE lines")
            }
            // SSE format: "data: {...}"
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))  // Remove "data: "

            // Check for stream end
            if jsonString == "[DONE]" { break }

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Parse event type
            let type = json["type"] as? String

            switch type {
            case "content_block_delta":
                // Extract text delta
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    accumulatedText += text
                    await onChunk(text)  // Stream chunk to UI
                }

            case "message_delta":
                // Final message metadata
                if let delta = json["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = parseStopReason(reason)
                }
                if let usage = json["usage"] as? [String: Int] {
                    outputTokens = usage["output_tokens"] ?? 0
                }

            case "message_start":
                // Initial metadata including cache stats
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Int] {
                    inputTokens = usage["input_tokens"] ?? 0
                    cacheCreationTokens = usage["cache_creation_input_tokens"] ?? 0
                    cacheReadTokens = usage["cache_read_input_tokens"] ?? 0
                }

            default:
                if linesProcessed <= 5 {
                    logger.debug("Ignoring event type: \(type ?? "unknown")")
                }
            }
        }

        let cacheStats: CacheStats? = (cacheCreationTokens > 0 || cacheReadTokens > 0)
            ? CacheStats(cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens)
            : nil

        if let stats = cacheStats {
            logger.info("Stream cache stats: \(stats.cacheReadTokens) read, \(stats.cacheCreationTokens) created")
        }

        logger.info("Stream completed: \(linesProcessed) lines, \(accumulatedText.count) chars, \(inputTokens) + \(outputTokens) tokens")

        let message = AgentMessage(
            role: .assistant,
            content: accumulatedText,
            toolCalls: nil
        )

        return AgentResponse(
            message: message,
            stopReason: stopReason,
            usage: AgentResponse.Usage(inputTokens: inputTokens, outputTokens: outputTokens),
            cacheStats: cacheStats
        )
    }

    // MARK: - Helpers

    private func messageToDict(_ message: AgentMessage) -> [String: Any] {
        // Anthropic uses a content array with blocks for caching support
        var contentBlock: [String: Any] = [
            "type": "text",
            "text": message.content
        ]

        // Add cache_control if present (for prompt caching)
        if let cacheControl = message.cacheControl {
            contentBlock["cache_control"] = ["type": cacheControl.type]
        }

        return [
            "role": message.role.rawValue,
            "content": [contentBlock]  // Array of content blocks (required for caching)
        ]
    }

    private func toolToDict(_ tool: Tool) -> [String: Any] {
        return [
            "name": tool.name,
            "description": tool.description,
            "input_schema": tool.inputSchema
        ]
    }

    private func parseResponse(_ json: [String: Any]) throws -> AgentResponse {
        guard let content = json["content"] as? [[String: Any]] else {
            throw AnthropicError.invalidResponse
        }

        let stopReason = parseStopReason(json["stop_reason"] as? String)

        // Parse usage including cache statistics
        let usage = json["usage"] as? [String: Int]
        let inputTokens = usage?["input_tokens"] ?? 0
        let outputTokens = usage?["output_tokens"] ?? 0

        // Extract cache statistics (Anthropic prompt caching)
        let cacheCreationTokens = usage?["cache_creation_input_tokens"] ?? 0
        let cacheReadTokens = usage?["cache_read_input_tokens"] ?? 0

        let cacheStats: CacheStats? = (cacheCreationTokens > 0 || cacheReadTokens > 0)
            ? CacheStats(cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens)
            : nil

        if let stats = cacheStats {
            logger.info("Cache stats: \(stats.cacheReadTokens) read, \(stats.cacheCreationTokens) created")
        }

        // Extract text from text blocks (Claude can return multiple content blocks)
        var textParts: [String] = []
        for block in content {
            if block["type"] as? String == "text",
               let text = block["text"] as? String {
                textParts.append(text)
            }
        }
        let text = textParts.joined(separator: "\n")

        // Parse tool calls if present
        var toolCalls: [ToolCall]? = nil
        if stopReason == .toolUse {
            toolCalls = try parseToolCalls(content)
        }

        let message = AgentMessage(
            role: .assistant,
            content: text,
            toolCalls: toolCalls
        )

        return AgentResponse(
            message: message,
            stopReason: stopReason,
            usage: AgentResponse.Usage(inputTokens: inputTokens, outputTokens: outputTokens),
            cacheStats: cacheStats
        )
    }

    private func parseStopReason(_ reason: String?) -> AgentResponse.StopReason {
        switch reason {
        case "end_turn": return .endTurn
        case "max_tokens": return .maxTokens
        case "tool_use": return .toolUse
        case "stop_sequence": return .stopSequence
        default: return .endTurn
        }
    }

    private func parseToolCalls(_ content: [[String: Any]]) throws -> [ToolCall] {
        var calls: [ToolCall] = []

        for block in content {
            if block["type"] as? String == "tool_use",
               let id = block["id"] as? String,
               let name = block["name"] as? String,
               let input = block["input"] as? [String: Any] {
                calls.append(ToolCall(id: id, name: name, arguments: input))
            }
        }

        return calls
    }
}

// MARK: - Errors

public enum AnthropicError: Error {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}
