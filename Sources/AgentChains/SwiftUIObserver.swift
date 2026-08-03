// AgentChains/SwiftUIObserver.swift
// SwiftUI-friendly observability for Interview Copilot UI

import Foundation
import SwiftUI
import AgentRunKit
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Agent UI State

/// Observable state for agent activity in SwiftUI
@available(iOS 15.0, macOS 12.0, *)
@MainActor
public class AgentUIState: ObservableObject {
    /// Current agent status
    @Published public var status: AgentStatus = .idle

    /// Latest suggestion/hint
    @Published public var currentSuggestion: AgentSuggestion?

    /// Tool call history
    @Published public var toolCalls: [ToolCallEntry] = []

    /// Current thinking message
    @Published public var thinkingMessage: String?

    /// Is agent processing?
    @Published public var isProcessing: Bool = false

    /// Error message
    @Published public var errorMessage: String?

    /// Response history
    @Published public var responses: [AgentResponse] = []

    /// Performance metrics
    @Published public var metrics: AgentMetrics = AgentMetrics()

    public init() {}

    /// Update from agent event
    public func update(event: AgentEvent) {
        Task { @MainActor in
            switch event {
            case .agentStarted(let task):
                status = .running
                isProcessing = true
                thinkingMessage = "Processing: \(task)"

            case .thinking(let message):
                thinkingMessage = message

            case .toolCalled(let name, let parameters):
                let entry = ToolCallEntry(
                    id: UUID(),
                    name: name,
                    parameters: parameters,
                    timestamp: Date(),
                    status: .running
                )
                toolCalls.append(entry)

            case .toolResult(let name, let result, let duration):
                if let index = toolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) {
                    toolCalls[index].status = .completed
                    toolCalls[index].result = result
                    toolCalls[index].duration = duration
                }
                metrics.totalToolCalls += 1

            case .toolError(let name, let error):
                if let index = toolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) {
                    toolCalls[index].status = .failed
                    toolCalls[index].error = error
                }

            case .response(let content):
                thinkingMessage = nil
                currentSuggestion = parseSuggestion(from: content)
                responses.append(AgentResponse(
                    id: UUID(),
                    content: content,
                    timestamp: Date()
                ))

            case .agentCompleted(let iterations, let duration):
                status = .completed
                isProcessing = false
                thinkingMessage = nil
                metrics.totalIterations = iterations
                metrics.totalDuration = duration

            case .agentError(let error):
                status = .error
                isProcessing = false
                errorMessage = error
                thinkingMessage = nil
            }
        }
    }

    /// Clear state
    public func clear() {
        status = .idle
        currentSuggestion = nil
        toolCalls.removeAll()
        thinkingMessage = nil
        isProcessing = false
        errorMessage = nil
        responses.removeAll()
    }

    /// Parse suggestion from response
    private func parseSuggestion(from content: String) -> AgentSuggestion {
        // Extract emoji icon if present
        let icon = content.first(where: { $0.isEmoji }) ?? "💡"

        // Split into title and details
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let title = lines.first ?? content
        let details = lines.dropFirst().joined(separator: "\n")

        return AgentSuggestion(
            id: UUID(),
            icon: String(icon),
            title: title.replacingOccurrences(of: String(icon), with: "").trimmingCharacters(in: .whitespaces),
            details: details.isEmpty ? nil : details,
            timestamp: Date(),
            priority: .normal
        )
    }
}

// MARK: - Supporting Types

public enum AgentStatus: Sendable {
    case idle
    case running
    case completed
    case error
}

public struct AgentSuggestion: Identifiable, Sendable {
    public let id: UUID
    public let icon: String
    public let title: String
    public let details: String?
    public let timestamp: Date
    public let priority: SuggestionPriority

    public init(id: UUID, icon: String, title: String, details: String?, timestamp: Date, priority: SuggestionPriority) {
        self.id = id
        self.icon = icon
        self.title = title
        self.details = details
        self.timestamp = timestamp
        self.priority = priority
    }
}

public enum SuggestionPriority: Sendable {
    case low, normal, high, urgent
}

public struct ToolCallEntry: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let parameters: String
    public let timestamp: Date
    public var status: ToolStatus
    public var result: String?
    public var error: String?
    public var duration: TimeInterval?

    public init(id: UUID, name: String, parameters: String, timestamp: Date, status: ToolStatus, result: String? = nil, error: String? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.timestamp = timestamp
        self.status = status
        self.result = result
        self.error = error
        self.duration = duration
    }
}

public enum ToolStatus: Sendable {
    case running, completed, failed
}

public struct AgentResponse: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let timestamp: Date

    public init(id: UUID, content: String, timestamp: Date) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
}

public struct AgentMetrics: Sendable {
    public var totalToolCalls: Int = 0
    public var totalIterations: Int = 0
    public var totalDuration: TimeInterval = 0

    public init() {}
}

// MARK: - SwiftUI Observer

@available(iOS 15.0, macOS 12.0, *)
public actor SwiftUIObserver: AgentEventHandler {
    private let state: AgentUIState

    public init(state: AgentUIState) {
        self.state = state
    }

    public func handle(event: AgentEvent) async {
        await state.update(event: event)
    }
}

// MARK: - SwiftUI Views

#if canImport(SwiftUI)
@available(iOS 15.0, macOS 12.0, *)
public struct AgentSuggestionCard: View {
    let suggestion: AgentSuggestion

    public init(suggestion: AgentSuggestion) {
        self.suggestion = suggestion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(suggestion.icon)
                    .font(.title2)

                Text(suggestion.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text(formatTimeAgo(suggestion.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let details = suggestion.details {
                Text(details)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

@available(iOS 15.0, macOS 12.0, *)
public struct AgentThinkingIndicator: View {
    let message: String?

    public init(message: String?) {
        self.message = message
    }

    public var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            if let msg = message {
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Thinking...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(white: 0.95))
        )
    }
}

@available(iOS 15.0, macOS 12.0, *)
public struct ToolCallsList: View {
    let toolCalls: [ToolCallEntry]

    public init(toolCalls: [ToolCallEntry]) {
        self.toolCalls = toolCalls
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool Activity")
                .font(.headline)
                .padding(.horizontal)

            ForEach(toolCalls) { call in
                ToolCallRow(call: call)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct ToolCallRow: View {
    let call: ToolCallEntry

    var body: some View {
        HStack {
            statusIcon
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(call.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let duration = call.duration {
                    Text("\(String(format: "%.2f", duration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if call.status == .running {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            Color(white: 0.95)
                .opacity(call.status == .completed ? 0.3 : 1.0)
        )
    }

    var statusIcon: some View {
        switch call.status {
        case .running: return Text("🔧")
        case .completed: return Text("✅")
        case .failed: return Text("❌")
        }
    }
}
#endif

// MARK: - Character Extensions

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
