// AgentChains/ReActAgent.swift
// ReAct (Reasoning + Acting) agent loop
// Iteratively: Think → Act (use tools) → Observe → repeat until done

import Foundation
import AgentCore
import AgentTools
import AgentMemory
import Logging

// MARK: - ReAct Agent

/// An agent that uses ReAct loop: reasoning and tool use
@MainActor
public final class ReActAgent {
    private let session: LanguageModelSession
    private let toolRegistry: ToolRegistry
    private let maxIterations: Int
    private let logger: Logger
    private var onProgress: (@Sendable (String) -> Void)?

    public init(
        session: LanguageModelSession,
        toolRegistry: ToolRegistry,
        maxIterations: Int = 10,
        logger: Logger = Logger(label: "ReActAgent")
    ) {
        self.session = session
        self.toolRegistry = toolRegistry
        self.maxIterations = maxIterations
        self.logger = logger
    }

    /// Run the agent on a task
    public func run(
        task: String,
        extendedThinking: Bool = true,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        self.onProgress = onProgress
        logger.info("Starting ReAct loop for task: \(task)")

        var iteration = 0
        var finalAnswer: String?

        while iteration < maxIterations {
            iteration += 1
            logger.info("Iteration \(iteration)/\(maxIterations)")
            onProgress?("🔄 Step \(iteration)/\(maxIterations): Thinking...")

            // Generate response with available tools
            let response = try await session.generate(
                prompt: iteration == 1 ? task : "Continue with the task",
                tools: toolRegistry.allToolDefinitions(),
                maxTokens: 8000,
                temperature: 0.7,
                extendedThinking: extendedThinking
            )

            // Check stop reason
            switch response.stopReason {
            case .endTurn:
                // Agent is done
                finalAnswer = response.message.content
                logger.info("Agent finished: \(response.message.content.prefix(100))...")
                break

            case .toolUse:
                // Agent wants to use tools
                guard let toolCalls = response.message.toolCalls else {
                    throw AgentError.invalidToolCall
                }

                logger.info("Agent requested \(toolCalls.count) tool calls")
                onProgress?("🔧 Executing \(toolCalls.count) tool(s)...")

                // Execute all tool calls
                var toolResults: [String] = []
                for (index, toolCall) in toolCalls.enumerated() {
                    let toolIcon = toolCall.name.contains("list") ? "📂" :
                                  toolCall.name.contains("read") ? "📄" :
                                  toolCall.name.contains("search") ? "🔍" :
                                  toolCall.name.contains("find") ? "🗂️" : "🔧"

                    onProgress?("\(toolIcon) \(toolCall.name) (\(index+1)/\(toolCalls.count))")

                    do {
                        let result = try await toolRegistry.execute(toolCall: toolCall)
                        toolResults.append("""
                        Tool: \(toolCall.name)
                        Result: \(result)
                        """)
                    } catch {
                        toolResults.append("""
                        Tool: \(toolCall.name)
                        Error: \(error.localizedDescription)
                        """)
                    }
                }

                // Add tool results to conversation
                let toolResultMessage = AgentMessage(
                    role: .user,
                    content: "Tool Results:\n\n" + toolResults.joined(separator: "\n\n")
                )
                session.addMessage(toolResultMessage)

            case .maxTokens:
                logger.warning("Hit max tokens, continuing...")
                continue

            case .stopSequence:
                finalAnswer = response.message.content
                break
            }

            if finalAnswer != nil {
                break
            }
        }

        guard let answer = finalAnswer else {
            throw AgentError.maxIterationsReached
        }

        return answer
    }
}

// MARK: - Errors

public enum AgentError: Error {
    case invalidToolCall
    case maxIterationsReached
    case noResponseGenerated
}
