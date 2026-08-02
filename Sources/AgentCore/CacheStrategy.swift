// AgentCore/CacheStrategy.swift
// Prompt caching strategies for 90% cost reduction
// Automatically places cache breakpoints for optimal cache hit rates

import Foundation

// MARK: - Cache Strategy

/// Strategy for placing prompt cache breakpoints
public enum CacheStrategy {
    /// No caching (default for short conversations)
    case none

    /// Cache system messages only (good for single-shot tasks)
    case systemOnly

    /// Cache system + last N messages (good for ongoing conversations)
    case rollingWindow(messageCount: Int)

    /// Cache everything except the last user message (maximum caching)
    case aggressive

    /// Custom strategy with manual breakpoint control
    case custom(shouldCache: (AgentMessage, Int) -> Bool)

    /// Recommended strategy based on conversation length
    public static func recommended(messageCount: Int) -> CacheStrategy {
        switch messageCount {
        case 0...2:
            return .none  // Too short to benefit from caching
        case 3...5:
            return .systemOnly  // Cache system prompt only
        case 6...20:
            return .rollingWindow(messageCount: 10)  // Cache last 10 messages
        default:
            return .aggressive  // Maximum caching for long conversations
        }
    }
}

// MARK: - Cache-Aware Message Builder

/// Builds messages with optimal cache control annotations
@MainActor
public final class CacheAwareMessageBuilder {
    private let strategy: CacheStrategy

    public init(strategy: CacheStrategy = .systemOnly) {
        self.strategy = strategy
    }

    /// Apply cache control to messages based on strategy
    public func applyCache(to messages: [AgentMessage]) -> [AgentMessage] {
        guard !messages.isEmpty else { return messages }

        switch strategy {
        case .none:
            return messages

        case .systemOnly:
            return applyCacheToSystem(messages)

        case .rollingWindow(let count):
            return applyCacheToWindow(messages, windowSize: count)

        case .aggressive:
            return applyCacheToAllButLast(messages)

        case .custom(let shouldCache):
            return applyCustomCache(messages, predicate: shouldCache)
        }
    }

    // MARK: - Private Helpers

    private func applyCacheToSystem(_ messages: [AgentMessage]) -> [AgentMessage] {
        return messages.enumerated().map { index, message in
            if message.role == .system {
                return withCacheControl(message)
            }
            return message
        }
    }

    private func applyCacheToWindow(_ messages: [AgentMessage], windowSize: Int) -> [AgentMessage] {
        guard messages.count > windowSize else {
            return applyCacheToAllButLast(messages)
        }

        let cacheStartIndex = messages.count - windowSize - 1

        return messages.enumerated().map { index, message in
            if index == cacheStartIndex && message.role != .user {
                // Place cache breakpoint at the start of the window
                return withCacheControl(message)
            } else if message.role == .system {
                // Also cache system messages
                return withCacheControl(message)
            }
            return message
        }
    }

    private func applyCacheToAllButLast(_ messages: [AgentMessage]) -> [AgentMessage] {
        guard messages.count > 1 else { return messages }

        // Cache everything except the last message (current user input)
        return messages.enumerated().map { index, message in
            if index < messages.count - 1 && shouldBeCached(message) {
                return withCacheControl(message)
            }
            return message
        }
    }

    private func applyCustomCache(
        _ messages: [AgentMessage],
        predicate: (AgentMessage, Int) -> Bool
    ) -> [AgentMessage] {
        return messages.enumerated().map { index, message in
            if predicate(message, index) {
                return withCacheControl(message)
            }
            return message
        }
    }

    private func shouldBeCached(_ message: AgentMessage) -> Bool {
        // Only cache substantial messages (>100 chars)
        // Anthropic charges for cache writes, so small messages aren't worth it
        message.content.count >= 100
    }

    private func withCacheControl(_ message: AgentMessage) -> AgentMessage {
        AgentMessage(
            role: message.role,
            content: message.content,
            toolCalls: message.toolCalls,
            toolCallId: message.toolCallId,
            cacheControl: AgentMessage.CacheControl(type: "ephemeral")
        )
    }
}

// MARK: - Cache Analytics

/// Tracks cache performance metrics
public struct CacheMetrics {
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var uncachedTokens: Int = 0

    public var totalTokens: Int {
        cacheCreationTokens + cacheReadTokens + uncachedTokens
    }

    public var cacheHitRate: Double {
        guard totalTokens > 0 else { return 0.0 }
        return Double(cacheReadTokens) / Double(totalTokens)
    }

    public var costSavings: Double {
        // Cache reads cost 10% of full price, writes cost 25% more
        // Assuming $15/1M input tokens for Sonnet 4.6
        let fullCost = Double(totalTokens) * 15.0 / 1_000_000.0
        let cachedCost = (Double(cacheReadTokens) * 0.1 + Double(cacheCreationTokens) * 1.25 + Double(uncachedTokens)) * 15.0 / 1_000_000.0
        return fullCost - cachedCost
    }

    public init() {}

    public mutating func record(usage: AgentResponse.Usage, cacheStats: CacheStats?) {
        uncachedTokens += usage.inputTokens

        if let stats = cacheStats {
            cacheCreationTokens += stats.cacheCreationTokens
            cacheReadTokens += stats.cacheReadTokens
        }
    }
}

/// Cache statistics from API response
public struct CacheStats: Sendable {
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    public init(cacheCreationTokens: Int, cacheReadTokens: Int) {
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

// MARK: - Enhanced Response with Cache Stats

extension AgentResponse {
    /// Enhanced usage stats including cache information
    public struct EnhancedUsage: Sendable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheStats: CacheStats?

        public var totalCost: Double {
            let inputCost: Double
            if let cache = cacheStats {
                // Cached reads: 10% cost, cache writes: 25% extra, normal: 100%
                inputCost = (Double(cache.cacheReadTokens) * 0.1 +
                           Double(cache.cacheCreationTokens) * 1.25 +
                           Double(inputTokens - cache.cacheReadTokens - cache.cacheCreationTokens)) * 15.0 / 1_000_000.0
            } else {
                inputCost = Double(inputTokens) * 15.0 / 1_000_000.0
            }

            // Output tokens: $75/1M for Sonnet 4.6
            let outputCost = Double(outputTokens) * 75.0 / 1_000_000.0

            return inputCost + outputCost
        }

        public init(inputTokens: Int, outputTokens: Int, cacheStats: CacheStats? = nil) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheStats = cacheStats
        }
    }
}
