// AgentChains/AgentObserver.swift
// Real-time observability for agent tool calls and responses

import Foundation
import AgentRunKit
import AgentTools
import Logging

// MARK: - Agent Events

/// Events that occur during agent execution
public enum AgentEvent: Sendable {
    case agentStarted(task: String)
    case thinking(message: String)
    case toolCalled(name: String, parameters: String)
    case toolResult(name: String, result: String, duration: TimeInterval)
    case toolError(name: String, error: String)
    case response(content: String)
    case agentCompleted(iterations: Int, duration: TimeInterval)
    case agentError(error: String)
}

// MARK: - Event Handler Protocol

/// Protocol for handling agent events
public protocol AgentEventHandler: Sendable {
    func handle(event: AgentEvent) async
}

// MARK: - Console Observer

/// Prints agent events to console in real-time
public actor ConsoleObserver: AgentEventHandler {
    private let colored: Bool
    private let verbose: Bool

    public init(colored: Bool = true, verbose: Bool = true) {
        self.colored = colored
        self.verbose = verbose
    }

    public func handle(event: AgentEvent) async {
        let output = format(event: event)
        print(output)
        fflush(stdout)  // Flush immediately for real-time display
    }

    private func format(event: AgentEvent) -> String {
        switch event {
        case .agentStarted(let task):
            return colored ? "\n\u{001B}[1;36m🤖 Agent Started\u{001B}[0m\nTask: \(task)\n" :
                           "\n🤖 Agent Started\nTask: \(task)\n"

        case .thinking(let message):
            return colored ? "\u{001B}[0;33m💭 \(message)\u{001B}[0m" :
                           "💭 \(message)"

        case .toolCalled(let name, let parameters):
            let header = colored ? "\u{001B}[1;35m🔧 Tool Called: \(name)\u{001B}[0m" :
                                  "🔧 Tool Called: \(name)"
            if verbose {
                return """
                \(header)
                Parameters:
                \(parameters)
                """
            }
            return header

        case .toolResult(let name, let result, let duration):
            let header = colored ? "\u{001B}[1;32m✅ Tool Result: \(name)\u{001B}[0m (\(String(format: "%.2f", duration))s)" :
                                  "✅ Tool Result: \(name) (\(String(format: "%.2f", duration))s)"
            if verbose {
                return """
                \(header)
                \(result.prefix(500))\(result.count > 500 ? "..." : "")
                """
            }
            return header

        case .toolError(let name, let error):
            return colored ? "\u{001B}[1;31m❌ Tool Error: \(name)\u{001B}[0m\n\(error)" :
                           "❌ Tool Error: \(name)\n\(error)"

        case .response(let content):
            return colored ? "\u{001B}[1;34m💬 Agent Response:\u{001B}[0m\n\(content)\n" :
                           "💬 Agent Response:\n\(content)\n"

        case .agentCompleted(let iterations, let duration):
            return colored ? "\u{001B}[1;32m✨ Completed in \(iterations) iteration\(iterations == 1 ? "" : "s") (\(String(format: "%.2f", duration))s)\u{001B}[0m\n" :
                           "✨ Completed in \(iterations) iteration\(iterations == 1 ? "" : "s") (\(String(format: "%.2f", duration))s)\n"

        case .agentError(let error):
            return colored ? "\u{001B}[1;31m🚨 Agent Error:\u{001B}[0m\n\(error)\n" :
                           "🚨 Agent Error:\n\(error)\n"
        }
    }
}

// MARK: - JSON Observer

/// Streams agent events as JSON (for UI integration)
public actor JSONObserver: AgentEventHandler {
    private let outputStream: AsyncStream<String>.Continuation

    public init(continuation: AsyncStream<String>.Continuation) {
        self.outputStream = continuation
    }

    public func handle(event: AgentEvent) async {
        let json = encodeEvent(event)
        outputStream.yield(json)
    }

    private func encodeEvent(_ event: AgentEvent) -> String {
        var dict: [String: Any] = [:]

        switch event {
        case .agentStarted(let task):
            dict = ["type": "agent_started", "task": task, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .thinking(let message):
            dict = ["type": "thinking", "message": message, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .toolCalled(let name, let parameters):
            dict = ["type": "tool_called", "name": name, "parameters": parameters, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .toolResult(let name, let result, let duration):
            dict = ["type": "tool_result", "name": name, "result": result, "duration": duration, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .toolError(let name, let error):
            dict = ["type": "tool_error", "name": name, "error": error, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .response(let content):
            dict = ["type": "response", "content": content, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .agentCompleted(let iterations, let duration):
            dict = ["type": "completed", "iterations": iterations, "duration": duration, "timestamp": ISO8601DateFormatter().string(from: Date())]

        case .agentError(let error):
            dict = ["type": "error", "error": error, "timestamp": ISO8601DateFormatter().string(from: Date())]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "{\"type\":\"error\",\"error\":\"Failed to encode event\"}"
    }
}

// MARK: - File Observer

/// Logs agent events to a file
public actor FileObserver: AgentEventHandler {
    private let fileHandle: FileHandle
    private let logPath: String

    public init(logPath: String) throws {
        self.logPath = logPath

        // Create file if doesn't exist
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logPath) {
            fileManager.createFile(atPath: logPath, contents: nil)
        }

        self.fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        try self.fileHandle.seekToEnd()
    }

    public func handle(event: AgentEvent) async {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(formatEvent(event))\n"

        if let data = line.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }

    private func formatEvent(_ event: AgentEvent) -> String {
        switch event {
        case .agentStarted(let task):
            return "AGENT_STARTED: \(task)"
        case .thinking(let message):
            return "THINKING: \(message)"
        case .toolCalled(let name, let parameters):
            return "TOOL_CALLED: \(name) | \(parameters)"
        case .toolResult(let name, let result, let duration):
            return "TOOL_RESULT: \(name) | \(duration)s | \(result.prefix(200))"
        case .toolError(let name, let error):
            return "TOOL_ERROR: \(name) | \(error)"
        case .response(let content):
            return "RESPONSE: \(content)"
        case .agentCompleted(let iterations, let duration):
            return "COMPLETED: \(iterations) iterations | \(duration)s"
        case .agentError(let error):
            return "ERROR: \(error)"
        }
    }

    deinit {
        try? fileHandle.close()
    }
}

// MARK: - Multi Observer

/// Broadcasts events to multiple observers
public actor MultiObserver: AgentEventHandler {
    private var observers: [AgentEventHandler]

    public init(observers: [AgentEventHandler] = []) {
        self.observers = observers
    }

    public func addObserver(_ observer: AgentEventHandler) {
        observers.append(observer)
    }

    public func handle(event: AgentEvent) async {
        for observer in observers {
            await observer.handle(event: event)
        }
    }
}

// MARK: - Observable Agent Wrapper

/// Wraps an agent with observability
public struct ObservableAgent<Context: ToolContext> {
    private let agent: Agent<Context>
    private let observer: AgentEventHandler?

    public init(agent: Agent<Context>, observer: AgentEventHandler? = nil) {
        self.agent = agent
        self.observer = observer
    }

    /// Run agent with observable tool calls
    public func run(
        task: String,
        context: Context,
        systemPrompt: String? = nil
    ) async throws -> String {
        let startTime = Date()

        await observer?.handle(event: .agentStarted(task: task))

        var iterations = 0
        var lastResponse = ""

        do {
            // Note: AgentRunKit's Agent.run() doesn't expose streaming yet
            // For now we wrap the final response
            // In production, you'd need to hook into AgentRunKit's internal loop

            await observer?.handle(event: .thinking(message: "Processing task..."))

            let result = try await agent.run(userMessage: task, context: context)

            // Extract final response from result
            lastResponse = result.content ?? ""
            iterations = result.iterations

            await observer?.handle(event: .response(content: lastResponse))

            let duration = Date().timeIntervalSince(startTime)
            await observer?.handle(event: .agentCompleted(iterations: iterations, duration: duration))

            return lastResponse

        } catch {
            await observer?.handle(event: .agentError(error: error.localizedDescription))
            throw error
        }
    }
}

// MARK: - Extension for AgentBuilder

extension AgentBuilder {
    /// Create observable agent with console output
    public static func createObservable(
        config: Configuration,
        colored: Bool = true,
        verbose: Bool = true
    ) throws -> ObservableAgent<MemoryToolsContext> {
        let agent = try create(config: config)
        let observer = ConsoleObserver(colored: colored, verbose: verbose)
        return ObservableAgent(agent: agent, observer: observer)
    }

    /// Create observable agent with custom observer
    public static func createObservable(
        config: Configuration,
        observer: AgentEventHandler
    ) throws -> ObservableAgent<MemoryToolsContext> {
        let agent = try create(config: config)
        return ObservableAgent(agent: agent, observer: observer)
    }

    /// Create observable agent with JSON streaming
    public static func createObservable(
        config: Configuration,
        jsonStream: AsyncStream<String>.Continuation
    ) throws -> ObservableAgent<MemoryToolsContext> {
        let agent = try create(config: config)
        let observer = JSONObserver(continuation: jsonStream)
        return ObservableAgent(agent: agent, observer: observer)
    }
}
