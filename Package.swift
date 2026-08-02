// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftAgents",
    platforms: [
        .macOS(.v15) // Using macOS 15 for now, will update to 26 when Xcode 27 is stable
    ],
    products: [
        .library(name: "SwiftAgents", targets: [
            "AgentCore", "AgentMemory", "AgentRAG",
            "AgentTools", "AgentChains", "AgentObservability",
        ]),
    ],
    dependencies: [
        // For now: Direct Anthropic API integration (no FoundationModels until macOS 27 GA)
        // We'll add Apple's foundation-models-utilities when Xcode 27 is stable

        // Vector store for RAG (sqlite-vec: no server needed)
        .package(url: "https://github.com/jkrukowski/SQLiteVec", from: "0.0.9"),

        // Concurrency primitives for agent loop
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),

        // Logging
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),

        // Retry logic and circuit breaker (production-tested)
        .package(url: "https://github.com/CorvidLabs/swift-retry", from: "0.1.0"),

        // OpenAI integration (chat, embeddings, function calling)
        .package(url: "https://github.com/MacPaw/OpenAI", branch: "main"),

        // TODO: Add back when network stable - binary download times out
        // .package(url: "https://github.com/jkrukowski/swift-embeddings", from: "0.1.0"),
    ],
    targets: [
        // Core: Wraps LLM backends behind a protocol
        .target(
            name: "AgentCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Retry", package: "swift-retry"),
                .product(name: "OpenAI", package: "OpenAI"),
            ]
        ),

        // Memory: Buffer/window/summarization, session persistence
        .target(
            name: "AgentMemory",
            dependencies: [
                "AgentCore",
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),

        // RAG: VectorStore protocol, document loaders, retrievers
        .target(
            name: "AgentRAG",
            dependencies: [
                "AgentCore",
                .product(name: "SQLiteVec", package: "SQLiteVec"),
                // TODO: Add back when network stable
                // .product(name: "Embeddings", package: "swift-embeddings"),
            ]
        ),

        // Tools: Tool registry, parallel/sequential composition
        .target(name: "AgentTools", dependencies: ["AgentCore"]),

        // Chains: ReAct loop + chain DSL
        .target(
            name: "AgentChains",
            dependencies: [
                "AgentCore", "AgentTools", "AgentMemory",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),

        // Observability: Tracing hooks
        .target(
            name: "AgentObservability",
            dependencies: [
                "AgentCore",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        .testTarget(
            name: "SwiftAgentsTests",
            dependencies: ["AgentCore", "AgentMemory", "AgentRAG", "AgentTools", "AgentChains"]
        ),
    ]
)
