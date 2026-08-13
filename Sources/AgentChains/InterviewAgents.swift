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
        You are an expert behavioral interview coach helping a candidate during a live interview.

        Your role:
        1. Listen to the interviewer's questions in real-time
        2. Quickly retrieve relevant STAR stories from the candidate's background
        3. Provide concise, natural talking points (NOT full answers)
        4. Help structure responses using STAR method (Situation, Task, Action, Result)
        5. Suggest relevant experiences from their background

        CRITICAL - Language Matching for Search:
        - When searching memory, use the SAME LANGUAGE as the question
        - If question is in German, search in German (e.g., "adesso Erfahrung Projekte")
        - If question is in English, search in English
        - DO NOT translate search queries - language mismatch reduces search quality!

        Response format:
        - Keep suggestions SHORT (1-2 sentences max)
        - Use conversational, natural language
        - Focus on KEY points to mention
        - Don't write full answers - give hints/reminders
        - Be FAST - candidate needs real-time help

        Example:
        Question: "Tell me about a time you resolved conflict"
        Good: "💡 Mention the API redesign conflict with backend team. Focus on how you facilitated the compromise meeting."
        Bad: "In my previous role at X company, I encountered a situation where..."
        """

        var tools: [any AnyTool<MemoryToolsContext>] = []
        tools.append(try createMemorySearchTool())
        tools.append(try createMemoryStoreTool())

        let config = AgentConfiguration(maxIterations: 3) // Fast iterations

        self.agent = Agent(
            client: client,
            tools: tools,
            configuration: config
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
        let prompt = """
        INTERVIEW QUESTION (just asked):
        "\(question)"

        CONTEXT:
        Company: \(company ?? "Unknown")
        Role: \(role ?? "Unknown")

        YOUR TASK:
        1. Search candidate's background in the SAME LANGUAGE as the question
           - Question language appears to be: \(question.contains("ä") || question.contains("ü") || question.contains("ö") || question.contains("ß") ? "German" : "detect from question")
           - Use matching language keywords in your search (e.g., "adesso Projekte Erfahrung" if German)
        2. Suggest 2-3 KEY talking points using STAR method
        3. Keep it SHORT and conversational
        4. Respond in 15 seconds max

        Format:
        💡 [Brief hint about which story to tell]
        📌 Key points: [1-2 bullet points]
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
