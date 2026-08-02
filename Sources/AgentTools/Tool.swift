// AgentTools/Tool.swift
// Tool protocol and registry for agent execution

import Foundation
import AgentCore
import Logging

// MARK: - Tool Protocol

/// A tool that an agent can use
public protocol AgentTool: Sendable {
    /// Unique tool name
    var name: String { get }

    /// Human-readable description for the LLM
    var description: String { get }

    /// JSON schema for input parameters
    var inputSchema: [String: Any] { get }

    /// Execute the tool with given parameters
    func execute(parameters: [String: Any]) async throws -> String
}

// MARK: - Tool Registry

/// Manages available tools and executes them
@MainActor
public final class ToolRegistry {
    private var tools: [String: AgentTool] = [:]
    private let logger: Logger

    public init(logger: Logger = Logger(label: "ToolRegistry")) {
        self.logger = logger
    }

    /// Register a tool
    public func register(_ tool: AgentTool) {
        tools[tool.name] = tool
        logger.info("Registered tool: \(tool.name)")
    }

    /// Get all registered tools as Tool definitions for the LLM
    public func allToolDefinitions() -> [Tool] {
        tools.values.map { tool in
            Tool(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema
            )
        }
    }

    /// Execute a tool call
    public func execute(toolCall: ToolCall) async throws -> String {
        guard let tool = tools[toolCall.name] else {
            logger.error("Tool not found: \(toolCall.name)")
            throw ToolError.toolNotFound(toolCall.name)
        }

        logger.info("Executing tool: \(toolCall.name) with \(toolCall.arguments.count) parameters")

        let startTime = Date()
        do {
            let result = try await tool.execute(parameters: toolCall.arguments)
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Tool \(toolCall.name) succeeded in \(String(format: "%.2f", duration))s")
            return result
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Tool \(toolCall.name) failed after \(String(format: "%.2f", duration))s: \(error)")
            throw error
        }
    }
}

// MARK: - Errors

public enum ToolError: Error {
    case toolNotFound(String)
    case executionFailed(String)
    case invalidParameters(String)
}
