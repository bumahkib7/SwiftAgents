// AgentCore/ResilientBackend.swift
// Production-grade resilient backend using swift-retry library
// Wraps any LanguageModelBackend with retry logic and circuit breaker

import Foundation
import Logging
import Retry

// MARK: - Resilient Backend

/// Wraps a language model backend with retry and circuit breaker protection
@available(iOS 13.0.0, *)
public actor ResilientBackend: LanguageModelBackend {
    private let backend: LanguageModelBackend
    private let circuitBreaker: CircuitBreaker
    private let logger: Logger

    // Retry configuration
    private let maxAttempts: Int
    private let strategy: any RetryStrategy
    private let jitter: any Jitter

    /// Create a resilient backend wrapper
    /// - Parameters:
    ///   - backend: The underlying backend to wrap
    ///   - maxAttempts: Maximum retry attempts (default: 3)
    ///   - failureThreshold: Circuit breaker opens after this many failures (default: 5)
    ///   - resetTimeout: Time before circuit breaker attempts recovery (default: 30s)
    ///   - logger: Logger instance
    public init(
        backend: LanguageModelBackend,
        maxAttempts: Int = 3,
        failureThreshold: Int = 5,
        resetTimeout: TimeInterval = 30.0,
        logger: Logger = Logger(label: "ResilientBackend")
    ) {
        self.backend = backend
        self.maxAttempts = maxAttempts
        self.strategy = ExponentialStrategy(base: 2.0, multiplier: 2.0)  // 2s, 4s, 8s...
        self.jitter = FullJitter()  // Prevents thundering herd
        self.circuitBreaker = CircuitBreaker(
            failureThreshold: failureThreshold,
            resetTimeout: resetTimeout
        )
        self.logger = logger
    }

    public nonisolated func generate(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool
    ) async throws -> AgentResponse {
        let config = RetryConfiguration(
            maxAttempts: maxAttempts,
            maxDelay: 30.0,  // Cap delays at 30 seconds
            shouldRetry: { error in
                // Retry on network errors, 5xx, and 429 rate limits
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                         .cannotFindHost, .cannotConnectToHost:
                        return true
                    default:
                        return false
                    }
                }

                if let anthropicError = error as? AnthropicError {
                    switch anthropicError {
                    case .apiError(let statusCode, _):
                        return (500...599).contains(statusCode) || statusCode == 429
                    default:
                        return false
                    }
                }

                return false
            }
        )

        return try await Retry.execute(
            maxAttempts: maxAttempts,
            strategy: strategy,
            jitter: jitter,
            circuitBreaker: circuitBreaker,
            configuration: config
        ) {
            try await backend.generate(
                messages: messages,
                tools: tools,
                maxTokens: maxTokens,
                temperature: temperature,
                extendedThinking: extendedThinking
            )
        }
    }

    public nonisolated func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse {
        let config = RetryConfiguration(
            maxAttempts: maxAttempts,
            maxDelay: 30.0,  // Cap delays at 30 seconds
            shouldRetry: { error in
                // Retry on network errors, 5xx, and 429 rate limits
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                        return true
                    default:
                        return false
                    }
                }

                if let anthropicError = error as? AnthropicError {
                    switch anthropicError {
                    case .apiError(let statusCode, _):
                        return (500...599).contains(statusCode) || statusCode == 429
                    default:
                        return false
                    }
                }

                return false
            }
        )

        return try await Retry.execute(
            maxAttempts: maxAttempts,
            strategy: strategy,
            jitter: jitter,
            circuitBreaker: circuitBreaker,
            configuration: config
        ) {
            try await backend.stream(
                messages: messages,
                tools: tools,
                maxTokens: maxTokens,
                temperature: temperature,
                extendedThinking: extendedThinking,
                onChunk: onChunk
            )
        }
    }

    /// Get current circuit breaker state for monitoring
    public var circuitState: CircuitState {
        get async {
            await circuitBreaker.currentState
        }
    }

    /// Reset the circuit breaker (for manual recovery)
    public func resetCircuit() async {
        await circuitBreaker.reset()
    }
}

// MARK: - Convenience Extensions

extension ResilientBackend {
    /// Production-ready defaults for Anthropic Claude
    public static func forAnthropic(
        apiKey: String,
        model: String = "claude-sonnet-4-20250514",
        logger: Logger = Logger(label: "ResilientBackend")
    ) -> ResilientBackend {
        let backend = AnthropicBackend(apiKey: apiKey, model: model, logger: logger)
        return ResilientBackend(
            backend: backend,
            maxAttempts: 3,
            failureThreshold: 5,
            resetTimeout: 30.0,
            logger: logger
        )
    }
}
