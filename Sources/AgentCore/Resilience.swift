// AgentCore/Resilience.swift
// Production-grade error handling, retry logic, and circuit breakers
// Prevents cascading failures and ensures graceful degradation

import Foundation
import Logging

// MARK: - Retry Policy

/// Defines how retries should behave
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let backoffMultiplier: Double
    public let jitter: Bool

    /// Default production retry policy: 3 attempts with exponential backoff
    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 2.0,          // Start with 2 seconds
        maxDelay: 30.0,          // Cap at 30 seconds
        backoffMultiplier: 2.0,  // 2s → 4s → 8s
        jitter: true             // Add randomness to prevent thundering herd
    )

    /// Aggressive retry for critical operations
    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        baseDelay: 1.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0,
        jitter: true
    )

    /// No retries (for testing or non-critical operations)
    public static let none = RetryPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0,
        jitter: false
    )

    public init(
        maxAttempts: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        backoffMultiplier: Double,
        jitter: Bool
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitter = jitter
    }

    /// Calculate delay for a given attempt
    func delay(for attempt: Int) -> TimeInterval {
        var delay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
        delay = min(delay, maxDelay)

        if jitter {
            // Add ±25% jitter to prevent thundering herd
            let jitterAmount = delay * 0.25
            let randomJitter = Double.random(in: -jitterAmount...jitterAmount)
            delay += randomJitter
        }

        return max(0, delay)
    }

    /// Check if an error is retryable
    func isRetryable(_ error: Error) -> Bool {
        // Retry on network errors, timeouts, 5xx server errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        if let anthropicError = error as? AnthropicError {
            switch anthropicError {
            case .apiError(let statusCode, _):
                // Retry on 5xx server errors and rate limits
                return (500...599).contains(statusCode) || statusCode == 429
            case .invalidResponse:
                return false  // Don't retry malformed responses
            }
        }

        return false
    }
}

// MARK: - Retry Executor

/// Executes operations with automatic retry logic
public actor RetryExecutor {
    private let policy: RetryPolicy
    private let logger: Logger

    public init(policy: RetryPolicy = .default, logger: Logger = Logger(label: "RetryExecutor")) {
        self.policy = policy
        self.logger = logger
    }

    /// Execute an operation with retry logic
    public func execute<T>(
        operation: @Sendable () async throws -> T,
        operationName: String = "Operation"
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...policy.maxAttempts {
            do {
                if attempt > 1 {
                    logger.info("[\(operationName)] Retry attempt \(attempt)/\(policy.maxAttempts)")
                }

                let result = try await operation()
                if attempt > 1 {
                    logger.info("[\(operationName)] Succeeded on attempt \(attempt)")
                }
                return result

            } catch {
                lastError = error

                if !policy.isRetryable(error) {
                    logger.warning("[\(operationName)] Non-retryable error: \(error.localizedDescription)")
                    throw error
                }

                if attempt < policy.maxAttempts {
                    let delay = policy.delay(for: attempt)
                    logger.warning("[\(operationName)] Attempt \(attempt) failed: \(error.localizedDescription). Retrying in \(String(format: "%.2f", delay))s...")

                    try await Task.sleep(for: .seconds(delay))
                } else {
                    logger.error("[\(operationName)] All \(policy.maxAttempts) attempts failed")
                }
            }
        }

        throw lastError ?? RetryError.allAttemptsFailed
    }
}

public enum RetryError: Error {
    case allAttemptsFailed
}

// MARK: - Circuit Breaker

/// Circuit breaker state
public enum CircuitState: Sendable {
    case closed        // Normal operation
    case open          // Failures exceeded threshold, rejecting requests
    case halfOpen      // Testing if backend has recovered
}

/// Circuit breaker for preventing cascading failures
public actor CircuitBreaker {
    private let failureThreshold: Int
    private let successThreshold: Int
    private let timeout: TimeInterval
    private let logger: Logger

    private var state: CircuitState = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?

    /// Default production circuit breaker: Open after 5 failures, half-open after 30s
    public init(
        failureThreshold: Int = 5,      // Open circuit after 5 consecutive failures
        successThreshold: Int = 2,       // Close circuit after 2 consecutive successes in half-open
        timeout: TimeInterval = 30.0,    // Wait 30s before trying again (half-open)
        logger: Logger = Logger(label: "CircuitBreaker")
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.timeout = timeout
        self.logger = logger
    }

    /// Execute an operation through the circuit breaker
    public func execute<T>(
        operation: @Sendable () async throws -> T,
        operationName: String = "Operation"
    ) async throws -> T {
        try await checkState()

        do {
            let result = try await operation()
            await recordSuccess(operationName: operationName)
            return result
        } catch {
            await recordFailure(error: error, operationName: operationName)
            throw error
        }
    }

    /// Check and potentially transition circuit state
    private func checkState() throws {
        switch state {
        case .closed:
            // Normal operation
            break

        case .open:
            // Check if timeout has elapsed
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= timeout {
                logger.info("Circuit breaker transitioning to half-open (testing recovery)")
                state = .halfOpen
                successCount = 0
            } else {
                throw CircuitBreakerError.circuitOpen
            }

        case .halfOpen:
            // Allow request to test if backend has recovered
            break
        }
    }

    private func recordSuccess(operationName: String) {
        switch state {
        case .closed:
            failureCount = 0  // Reset failure count on success

        case .halfOpen:
            successCount += 1
            if successCount >= successThreshold {
                logger.info("[\(operationName)] Circuit breaker closing (backend recovered)")
                state = .closed
                failureCount = 0
                successCount = 0
            }

        case .open:
            break  // Should not happen
        }
    }

    private func recordFailure(error: Error, operationName: String) {
        switch state {
        case .closed:
            failureCount += 1
            lastFailureTime = Date()

            if failureCount >= failureThreshold {
                logger.error("[\(operationName)] Circuit breaker opening (threshold reached: \(failureCount) failures)")
                state = .open
            }

        case .halfOpen:
            // Failed while testing - go back to open
            logger.warning("[\(operationName)] Circuit breaker reopening (recovery test failed)")
            state = .open
            lastFailureTime = Date()

        case .open:
            lastFailureTime = Date()  // Reset timeout
        }
    }

    /// Get current state (for monitoring)
    public func getState() -> CircuitState {
        state
    }

    /// Reset circuit breaker (for manual recovery)
    public func reset() {
        state = .closed
        failureCount = 0
        successCount = 0
        lastFailureTime = nil
        logger.info("Circuit breaker manually reset")
    }
}

public enum CircuitBreakerError: LocalizedError {
    case circuitOpen

    public var errorDescription: String? {
        switch self {
        case .circuitOpen:
            return "Circuit breaker is open - backend is unavailable. Retrying soon."
        }
    }
}

// MARK: - Resilient Backend Wrapper

/// Wraps a language model backend with retry and circuit breaker
public actor ResilientBackend: LanguageModelBackend {
    private let backend: LanguageModelBackend
    private let retryExecutor: RetryExecutor
    private let circuitBreaker: CircuitBreaker
    private let logger: Logger

    public init(
        backend: LanguageModelBackend,
        retryPolicy: RetryPolicy = .default,
        logger: Logger = Logger(label: "ResilientBackend")
    ) {
        self.backend = backend
        self.retryExecutor = RetryExecutor(policy: retryPolicy, logger: logger)
        self.circuitBreaker = CircuitBreaker(logger: logger)
        self.logger = logger
    }

    public nonisolated func generate(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool
    ) async throws -> AgentResponse {
        try await circuitBreaker.execute(operation: {
            try await retryExecutor.execute(operation: {
                try await backend.generate(
                    messages: messages,
                    tools: tools,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    extendedThinking: extendedThinking
                )
            }, operationName: "generate")
        }, operationName: "generate")
    }

    public nonisolated func stream(
        messages: [AgentMessage],
        tools: [Tool],
        maxTokens: Int,
        temperature: Double,
        extendedThinking: Bool,
        onChunk: @Sendable (String) async -> Void
    ) async throws -> AgentResponse {
        try await circuitBreaker.execute(operation: {
            try await retryExecutor.execute(operation: {
                try await backend.stream(
                    messages: messages,
                    tools: tools,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    extendedThinking: extendedThinking,
                    onChunk: onChunk
                )
            }, operationName: "stream")
        }, operationName: "stream")
    }

    /// Get circuit breaker state for monitoring
    public func getCircuitState() async -> CircuitState {
        await circuitBreaker.getState()
    }

    /// Reset circuit breaker manually
    public func resetCircuit() async {
        await circuitBreaker.reset()
    }
}
