// AgentChains/InterviewAgents.swift
// Specialized agents for technical interviews (behavioral, coding, system design)

import Foundation
import AgentRunKit
import AgentRAG
import AgentTools
import Logging

// MARK: - Interview Context

// Interview agents use MemoryToolsContext from AgentTools
// Interview metadata passed via prompts

/// Types of technical interviews
public enum InterviewType: String, Codable, Sendable {
    case behavioral
    case coding
    case systemDesign
    case technical
    case general
}

// MARK: - Behavioral Interview Agent

/// Create behavioral interview agent
public struct BehavioralInterviewAgent {
    private let agent: Agent<MemoryToolsContext>
    private let logger: Logger

    public init(client: any LLMClient, vectorStore: VectorStore, embedder: EmbeddingProvider) throws {
        let systemPrompt = """
        You ARE the candidate in a live interview. Answer as yourself using SPECIFIC facts from your CV.

        CRITICAL RULES:
        1. Search CV/documents for SPECIFIC data (company names, dates, technologies, projects)
        2. Use ACTUAL details from search results - NO generic answers
        3. Answer in SAME language as question
        4. Speak naturally in first person ("Ich habe..." / "I worked...")
        5. NEVER ask follow-up questions - just answer what was asked
        6. NO bullets/emojis/headers - natural speech only
        7. If search finds specific details, USE THEM (dates, project names, metrics)

        Example:
        Q: "Was hast du bei adesso gemacht?"
        BAD: "Bei adesso war ich Senior Engineer und habe Backend entwickelt... Gibt es ein spezielles Projekt?"
        GOOD: "Bei adesso von August 2023 bis Juli 2025 war ich Full-Stack Entwickler in der Versicherungsbranche. Ich habe Java 8 zu Java 21 Migration durchgeführt, Microservices modernisiert, und CI/CD Pipeline mit Jenkins und OpenShift aufgebaut."
        """

        var tools: [any AnyTool<MemoryToolsContext>] = []
        tools.append(try createMemorySearchTool())
        tools.append(try createMemoryStoreTool())

        // Allow deeper search for detailed questions, fast for simple ones
        let config = AgentConfiguration(
            maxIterations: 5,  // Allow thorough search when needed
            maxTokens: nil     // No hard limit - let continuation handle long answers
        )

        self.agent = Agent(
            client: client,
            tools: tools,
            configuration: config,
            systemPrompt: systemPrompt
        )
        self.logger = Logger(label: "BehavioralAgent")
    }

    /// Process interviewer question and suggest response
    public func suggestResponse(
        question: String,
        company: String? = nil,
        role: String? = nil,
        context: MemoryToolsContext
    ) async throws -> String {
        // Token-efficient prompt - details are in systemPrompt
        let prompt = """
        Q: \(question)
        Company: \(company ?? "?") | Role: \(role ?? "?")
        """

        let result = try await agent.run(userMessage: prompt, context: context)
        return result.content ?? "No suggestion available"
    }
}

// MARK: - Coding Interview Agent

/// Create coding interview agent
public struct CodingInterviewAgent {
    private let agent: Agent<MemoryToolsContext>
    private let logger: Logger

    public init(client: any LLMClient, vectorStore: VectorStore, embedder: EmbeddingProvider) throws {
        let systemPrompt = """
        You are an expert coding interview assistant helping during a LIVE coding interview.

        Your role:
        1. Listen to coding problems in real-time
        2. Quickly identify problem patterns (two pointers, sliding window, etc.)
        3. Suggest high-level approach WITHOUT giving full solution
        4. Help with hints when candidate is stuck
        5. Suggest time/space complexity considerations

        CRITICAL RULES:
        - DO NOT write full code solutions (that's cheating!)
        - Give HINTS and PATTERNS, not answers
        - Keep responses under 3 sentences
        - Be FAST - interviewer might be watching screen
        - Use natural language, not formal
        - Focus on thought process, not implementation

        Example:
        Problem: "Find two numbers that sum to target"
        Good: "💡 Hash table pattern - as you iterate, check if target-current exists in set"
        Bad: "Here's the solution: def twoSum(nums, target): seen = {}..."
        """

        var tools: [any AnyTool<MemoryToolsContext>] = []
        tools.append(try createMemorySearchTool())
        tools.append(try createWebSearchTool())
        tools.append(try createCodeExecutorTool())

        let config = AgentConfiguration(maxIterations: 2)

        self.agent = Agent(
            client: client,
            tools: tools,
            configuration: config
        )
        self.logger = Logger(label: "CodingAgent")
    }

    /// Get hint for coding problem
    public func getHint(
        problem: String,
        currentCode: String?,
        context: MemoryToolsContext
    ) async throws -> String {
        let prompt = """
        CODING PROBLEM:
        \(problem)

        CURRENT CODE (if any):
        \(currentCode ?? "Not started yet")

        YOUR TASK:
        1. Identify the problem pattern
        2. Suggest high-level approach (NO full code!)
        3. Give 1 specific hint if they're stuck
        4. Mention time/space complexity to consider

        Keep it under 3 sentences. Be helpful but don't give away the answer.
        """

        let result = try await agent.run(userMessage: prompt, context: context)
        return result.content ?? "Consider the problem constraints and edge cases"
    }

    /// Validate approach before implementing
    public func validateApproach(
        approach: String,
        context: MemoryToolsContext
    ) async throws -> String {
        let prompt = """
        CANDIDATE'S PROPOSED APPROACH:
        \(approach)

        Quick validation:
        1. Will this work? Any edge cases missed?
        2. Time/space complexity reasonable?
        3. Any optimization suggestions?

        One sentence response.
        """

        let result = try await agent.run(userMessage: prompt, context: context)
        return result.content ?? "Approach looks reasonable"
    }
}

// MARK: - System Design Interview Agent

/// Create system design interview agent
public struct SystemDesignAgent {
    private let agent: Agent<MemoryToolsContext>
    private let logger: Logger

    public init(client: any LLMClient, vectorStore: VectorStore, embedder: EmbeddingProvider) throws {
        let systemPrompt = """
        You are an expert system design interview coach helping during a LIVE system design interview.

        Your role:
        1. Listen to system design questions
        2. Suggest architectural components to discuss
        3. Remind about scalability considerations
        4. Help structure the discussion (requirements → design → deep dives)
        5. Suggest technologies when appropriate

        Response style:
        - CONCISE bullet points
        - Focus on what to discuss next
        - Remind about trade-offs
        - Keep under 4 lines
        - Natural, conversational tone

        Example:
        Question: "Design Twitter"
        Good:
        "📐 Start with:
        • Clarify: Read-heavy? Write QPS?
        • Core: Tweet service, Timeline service, User graph
        • Consider: Fanout on write vs read for timeline"

        Bad: "First, we need to understand the requirements. Twitter is a social media platform..."
        """

        var tools: [any AnyTool<MemoryToolsContext>] = []
        tools.append(try createMemorySearchTool())
        tools.append(try createWebSearchTool())

        let config = AgentConfiguration(maxIterations: 2)

        self.agent = Agent(
            client: client,
            tools: tools,
            configuration: config
        )
        self.logger = Logger(label: "SystemDesignAgent")
    }

    /// Get design suggestion
    public func suggestDesign(
        problem: String,
        currentDiscussion: String,
        context: MemoryToolsContext
    ) async throws -> String {
        let prompt = """
        SYSTEM DESIGN PROBLEM:
        \(problem)

        WHAT'S BEEN DISCUSSED:
        \(currentDiscussion)

        YOUR TASK:
        Suggest what to discuss next in 3-4 bullet points.
        Focus on what interviewer likely wants to hear.
        """

        let result = try await agent.run(userMessage: prompt, context: context)
        return result.content ?? "Consider scalability and trade-offs"
    }

    /// Get technology suggestions
    public func suggestTechnologies(
        requirement: String,
        context: MemoryToolsContext
    ) async throws -> String {
        let prompt = """
        REQUIREMENT:
        \(requirement)

        Suggest 2-3 technology choices with brief rationale (one line each).
        Example: "Redis - sub-ms latency for session cache"
        """

        let result = try await agent.run(userMessage: prompt, context: context)
        return result.content ?? "Standard industry technologies would work"
    }
}

// MARK: - AI Provider

/// Supported AI providers for interview agents
public enum AIProvider: String, Codable, Sendable {
    case openai
    case anthropic
    case gemini
}

// MARK: - Interview Agent Builder

/// Builder for creating interview-specific agents with any major AI provider
public struct InterviewAgentBuilder {

    /// Create behavioral interview agent
    public static func createBehavioral(
        apiKey: String,
        model: String,
        provider: AIProvider = .openai,
        vectorStore: VectorStore,
        embedder: EmbeddingProvider
    ) throws -> BehavioralInterviewAgent {
        let client: any LLMClient

        switch provider {
        case .openai:
            client = OpenAIClient.openAI(
                apiKey: apiKey,
                model: model,
                maxTokens: 500
            )
        case .anthropic:
            client = try AnthropicClient(
                apiKey: apiKey,
                model: model,
                maxTokens: 500
            )
        case .gemini:
            client = GeminiClient(
                apiKey: apiKey,
                model: model,
                maxOutputTokens: 500
            )
        }

        return try BehavioralInterviewAgent(
            client: client,
            vectorStore: vectorStore,
            embedder: embedder
        )
    }

    /// Create coding interview agent
    public static func createCoding(
        apiKey: String,
        model: String,
        provider: AIProvider = .openai,
        vectorStore: VectorStore,
        embedder: EmbeddingProvider
    ) throws -> CodingInterviewAgent {
        let client: any LLMClient

        switch provider {
        case .openai:
            client = OpenAIClient.openAI(
                apiKey: apiKey,
                model: model,
                maxTokens: 300
            )
        case .anthropic:
            client = try AnthropicClient(
                apiKey: apiKey,
                model: model,
                maxTokens: 300
            )
        case .gemini:
            client = GeminiClient(
                apiKey: apiKey,
                model: model,
                maxOutputTokens: 300
            )
        }

        return try CodingInterviewAgent(
            client: client,
            vectorStore: vectorStore,
            embedder: embedder
        )
    }

    /// Create system design interview agent
    public static func createSystemDesign(
        apiKey: String,
        model: String,
        provider: AIProvider = .openai,
        vectorStore: VectorStore,
        embedder: EmbeddingProvider
    ) throws -> SystemDesignAgent {
        let client: any LLMClient

        switch provider {
        case .openai:
            client = OpenAIClient.openAI(
                apiKey: apiKey,
                model: model,
                maxTokens: 400
            )
        case .anthropic:
            client = try AnthropicClient(
                apiKey: apiKey,
                model: model,
                maxTokens: 400
            )
        case .gemini:
            client = GeminiClient(
                apiKey: apiKey,
                model: model,
                maxOutputTokens: 400
            )
        }

        return try SystemDesignAgent(
            client: client,
            vectorStore: vectorStore,
            embedder: embedder
        )
    }
}
