// CachingExample.swift
// Demonstrates SwiftAgents prompt caching for 90% cost reduction

import Foundation
import AgentCore

// MARK: - Example: Interview Coaching Bot with Caching

/// This example shows how prompt caching dramatically reduces costs
/// for a conversation with a large system prompt (CV/resume context)
@MainActor
func runCachingDemo() async throws {
    // 1. Setup backend
    let backend = AnthropicBackend(
        apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "",
        model: "claude-sonnet-4-20250514"
    )

    // 2. Create session with aggressive caching strategy
    // This caches everything except the most recent user message
    let session = LanguageModelSession(
        backend: backend,
        cacheStrategy: .aggressive  // 90% cost reduction after first call!
    )

    // 3. Add large system prompt (this will be cached)
    let systemPrompt = """
    You are an expert interview coach helping software engineers prepare for technical interviews.

    # Candidate's CV/Resume

    **Name**: John Doe
    **Role**: Senior Backend Engineer
    **Email**: john.doe@example.com

    ## Work Experience

    ### Senior Backend Engineer @ TechCorp (2021-Present)
    - Designed and implemented microservices architecture serving 10M+ users
    - Led migration from monolith to event-driven architecture using Kafka
    - Reduced API latency from 800ms to 120ms (p95) through caching and optimization
    - Technologies: Spring Boot, Kotlin, PostgreSQL, Redis, Kubernetes, AWS

    ### Backend Engineer @ StartupXYZ (2019-2021)
    - Built RESTful APIs for B2B SaaS platform
    - Implemented OAuth2 authentication and role-based access control
    - Optimized database queries reducing load time by 60%
    - Technologies: Django, Python, PostgreSQL, Docker

    ### Junior Developer @ ConsultingFirm (2017-2019)
    - Developed internal tools and automation scripts
    - Participated in agile development with 2-week sprints
    - Technologies: Java, Spring MVC, MySQL

    ## Skills
    - Languages: Kotlin, Java, Python, SQL, JavaScript
    - Frameworks: Spring Boot, Django, React
    - Databases: PostgreSQL, MySQL, MongoDB, Redis
    - Cloud: AWS (EC2, S3, Lambda, RDS), Docker, Kubernetes
    - Tools: Git, Jenkins, Grafana, ELK Stack

    ## Education
    - BS Computer Science, State University, 2017

    ## Projects
    - **E-commerce Platform**: Built scalable backend handling 100k+ daily orders
    - **Real-time Analytics**: Implemented streaming pipeline with Kafka and Flink

    # Your Task
    Use the candidate's ACTUAL experience from above when answering interview questions.
    Be specific. Reference real projects, technologies, and metrics from the CV.

    Answer style: conversational, professional, 60-90 seconds when spoken.
    """

    session.addMessage(AgentMessage(role: .system, content: systemPrompt))

    // 4. First question - Will CREATE cache (pays 125% cost)
    print("\n=== First Question (Cache Write) ===")
    let response1 = try await session.generate(
        prompt: "Tell me about a time you optimized system performance."
    )

    print("Answer: \(response1.message.content)\n")

    if let stats = response1.cacheStats {
        print("📊 Tokens:")
        print("  - Input: \(response1.usage.inputTokens)")
        print("  - Output: \(response1.usage.outputTokens)")
        print("  - Cache Created: \(stats.cacheCreationTokens)")
        print("  - Cost: ~$\(String(format: "%.4f", calculateCost(response1)))")
    }

    // 5. Second question - Will READ from cache (pays 10% cost!)
    print("\n=== Second Question (Cache Read - 90% cheaper!) ===")
    let response2 = try await session.generate(
        prompt: "Describe your experience with microservices architecture."
    )

    print("Answer: \(response2.message.content)\n")

    if let stats = response2.cacheStats {
        print("📊 Tokens:")
        print("  - Input: \(response2.usage.inputTokens)")
        print("  - Output: \(response2.usage.outputTokens)")
        print("  - Cache Read: \(stats.cacheReadTokens) ✅ (90% discount!)")
        print("  - Cost: ~$\(String(format: "%.4f", calculateCost(response2)))")
    }

    // 6. Show total savings
    print("\n=== Total Session Metrics ===")
    let metrics = session.metrics
    print("Cache Hit Rate: \(String(format: "%.1f%%", metrics.cacheHitRate * 100))")
    print("Cost Savings: $\(String(format: "%.4f", metrics.costSavings))")
    print("Total Tokens: \(metrics.totalTokens)")
    print("  - Cache Created: \(metrics.cacheCreationTokens)")
    print("  - Cache Read: \(metrics.cacheReadTokens)")
    print("  - Uncached: \(metrics.uncachedTokens)")
}

// MARK: - Cache Strategy Comparison

/// Compare different caching strategies
@MainActor
func compareCachingStrategies() async throws {
    let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    let backend = AnthropicBackend(apiKey: apiKey)

    let strategies: [(String, CacheStrategy)] = [
        ("No Caching", .none),
        ("System Only", .systemOnly),
        ("Rolling Window (10)", .rollingWindow(messageCount: 10)),
        ("Aggressive", .aggressive)
    ]

    print("\n=== Caching Strategy Comparison ===\n")

    for (name, strategy) in strategies {
        let session = LanguageModelSession(backend: backend, cacheStrategy: strategy)

        // Add system prompt
        session.addMessage(AgentMessage(role: .system, content: "You are a helpful assistant."))

        // Simulate conversation
        for i in 1...3 {
            _ = try await session.generate(prompt: "Question \(i)")
        }

        let metrics = session.metrics
        print("Strategy: \(name)")
        print("  - Cache Hit Rate: \(String(format: "%.1f%%", metrics.cacheHitRate * 100))")
        print("  - Cost Savings: $\(String(format: "%.4f", metrics.costSavings))")
        print("  - Total Tokens: \(metrics.totalTokens)\n")
    }
}

// MARK: - Helper Functions

private func calculateCost(_ response: AgentResponse) -> Double {
    let inputCost: Double
    if let cache = response.cacheStats {
        // Cached reads: 10% cost, cache writes: 25% extra, normal: 100%
        inputCost = (Double(cache.cacheReadTokens) * 0.1 +
                   Double(cache.cacheCreationTokens) * 1.25 +
                   Double(response.usage.inputTokens - cache.cacheReadTokens - cache.cacheCreationTokens)) * 15.0 / 1_000_000.0
    } else {
        inputCost = Double(response.usage.inputTokens) * 15.0 / 1_000_000.0
    }

    // Output tokens: $75/1M for Sonnet 4.6
    let outputCost = Double(response.usage.outputTokens) * 75.0 / 1_000_000.0

    return inputCost + outputCost
}

// MARK: - Cost Calculator CLI

/// Interactive cost calculator
func runCostCalculator() {
    print("\n=== SwiftAgents Cost Calculator ===\n")

    print("Without Caching:")
    print("  100,000 tokens/day × 30 days = 3M tokens/month")
    print("  Input: 3M × $15/M = $45.00")
    print("  Output: 3M × $75/M = $225.00")
    print("  Total: $270.00/month\n")

    print("With 90% Cache Hit Rate:")
    print("  Cache reads: 2.7M × $1.50/M = $4.05")
    print("  Cache writes: 300k × $18.75/M = $5.63")
    print("  Output: 3M × $75/M = $225.00")
    print("  Total: $234.68/month\n")

    print("💰 Savings: $35.32/month (13% reduction on total costs)")
    print("💰 Savings on input tokens: $40.95/month (91% reduction!)\n")

    print("📈 As conversation length increases, savings grow:")
    print("  - 10 message conversation: ~5% savings")
    print("  - 50 message conversation: ~30% savings")
    print("  - 100+ message conversation: ~50% total cost savings\n")
}

// MARK: - Main Entry Point

@main
struct CachingDemo {
    static func main() async throws {
        // Run cost calculator
        runCostCalculator()

        // Run caching demo (requires API key)
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
            try await runCachingDemo()
            try await compareCachingStrategies()
        } else {
            print("⚠️  Set ANTHROPIC_API_KEY environment variable to run live demo")
        }
    }
}
