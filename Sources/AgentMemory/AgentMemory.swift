// AgentMemory/AgentMemory.swift
// Conversation buffer, windowing, and session persistence

import Foundation
import AgentCore
import Collections

// MARK: - Conversation Buffer

/// Manages conversation history with configurable windowing and memory limits
@MainActor
public final class ConversationBuffer {
    private var messages: Deque<AgentMessage>
    private let maxMessages: Int
    private let maxTokens: Int

    public init(maxMessages: Int = 50, maxTokens: Int = 8000) {
        self.messages = []
        self.maxMessages = maxMessages
        self.maxTokens = maxTokens
    }

    /// Add a message to the buffer
    public func add(_ message: AgentMessage) {
        messages.append(message)
        enforceLimits()
    }

    /// Add multiple messages
    public func addAll(_ newMessages: [AgentMessage]) {
        messages.append(contentsOf: newMessages)
        enforceLimits()
    }

    /// Get all messages in the buffer
    public func getMessages() -> [AgentMessage] {
        Array(messages)
    }

    /// Get recent messages up to a token limit
    public func getRecent(maxTokens: Int) -> [AgentMessage] {
        var result: [AgentMessage] = []
        var tokenCount = 0

        for message in messages.reversed() {
            let messageTokens = estimateTokens(message.content)
            if tokenCount + messageTokens > maxTokens {
                break
            }
            result.insert(message, at: 0)
            tokenCount += messageTokens
        }

        return result
    }

    /// Clear all messages
    public func clear() {
        messages.removeAll()
    }

    /// Get message count
    public var count: Int {
        messages.count
    }

    // MARK: - Private

    private func enforceLimits() {
        // Enforce message count limit
        while messages.count > maxMessages {
            messages.removeFirst()
        }

        // Enforce token limit
        var totalTokens = messages.map { estimateTokens($0.content) }.reduce(0, +)
        while totalTokens > maxTokens && !messages.isEmpty {
            let removed = messages.removeFirst()
            totalTokens -= estimateTokens(removed.content)
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimate: ~4 characters per token
        text.count / 4
    }
}

// MARK: - Memory Strategies

/// Strategy for managing memory when buffer fills up
public enum MemoryStrategy {
    case truncate          // Remove oldest messages
    case summarize         // Summarize old messages (requires LLM call)
    case compress          // Smart compression based on importance
}

/// Memory manager with different retention strategies
@MainActor
public final class AgentMemory {
    private let buffer: ConversationBuffer
    private let strategy: MemoryStrategy
    private var summaries: [String] = []

    public init(
        maxMessages: Int = 50,
        maxTokens: Int = 8000,
        strategy: MemoryStrategy = .truncate
    ) {
        self.buffer = ConversationBuffer(maxMessages: maxMessages, maxTokens: maxTokens)
        self.strategy = strategy
    }

    /// Add a conversation turn (user question + assistant answer)
    public func addTurn(question: String, answer: String, context: [String: Any] = [:]) {
        let userMessage = AgentMessage(role: .user, content: question)
        let assistantMessage = AgentMessage(role: .assistant, content: answer)

        buffer.add(userMessage)
        buffer.add(assistantMessage)
    }

    /// Get conversation history for context
    public func getContext(maxTokens: Int) -> [AgentMessage] {
        buffer.getRecent(maxTokens: maxTokens)
    }

    /// Get all messages
    public func getAllMessages() -> [AgentMessage] {
        buffer.getMessages()
    }

    /// Clear memory
    public func clear() {
        buffer.clear()
        summaries.removeAll()
    }

    /// Save conversation to disk
    public func save(to url: URL) throws {
        let messages = buffer.getMessages()
        let data = try JSONEncoder().encode(messages)
        try data.write(to: url)
    }

    /// Load conversation from disk
    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let messages = try JSONDecoder().decode([AgentMessage].self, from: data)
        buffer.addAll(messages)
    }
}

// MARK: - Session Persistence

/// Persistent storage for agent sessions
public struct AgentSession: Codable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public var messages: [AgentMessage]
    public var metadata: [String: String]

    public init(id: UUID = UUID(), startTime: Date = Date(), messages: [AgentMessage] = [], metadata: [String: String] = [:]) {
        self.id = id
        self.startTime = startTime
        self.messages = messages
        self.metadata = metadata
    }
}

/// Manages persistent agent sessions
public actor SessionStore {
    private let storageURL: URL

    public init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageURL = dir
        } else {
            // Default to app support directory
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageURL = appSupport.appendingPathComponent("AgentSessions")
        }

        // Create directory if needed
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    /// Save a session
    public func save(_ session: AgentSession) throws {
        let url = storageURL.appendingPathComponent("\(session.id.uuidString).json")
        let data = try JSONEncoder().encode(session)
        try data.write(to: url)
    }

    /// Load a session by ID
    public func load(_ id: UUID) throws -> AgentSession {
        let url = storageURL.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AgentSession.self, from: data)
    }

    /// List all sessions
    public func listSessions() throws -> [AgentSession] {
        let files = try FileManager.default.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        return try jsonFiles.compactMap { url in
            let data = try Data(contentsOf: url)
            return try? JSONDecoder().decode(AgentSession.self, from: data)
        }.sorted { $0.startTime > $1.startTime }
    }

    /// Delete a session
    public func delete(_ id: UUID) throws {
        let url = storageURL.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }

    /// Clear all sessions
    public func clearAll() throws {
        let files = try FileManager.default.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }
}
