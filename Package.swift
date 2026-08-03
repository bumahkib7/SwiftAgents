// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftAgents",
    platforms: [
        .macOS(.v15) // Using macOS 15 for now, will update to 26 when Xcode 27 is stable
    ],
    products: [
        .library(name: "SwiftAgents", targets: [
            "AgentRAG", "AgentTools", "AgentChains",
        ]),
    ],
    dependencies: [
        // For now: Direct Anthropic API integration (no FoundationModels until macOS 27 GA)
        // We'll add Apple's foundation-models-utilities when Xcode 27 is stable

        // Vector store for RAG (sqlite-vec: OPTIONAL - has macOS compatibility issues)
        // Use InMemoryVectorStore for development or if SQLiteVec fails to compile
        // .package(url: "https://github.com/jkrukowski/SQLiteVec", from: "0.0.9"),

        // Concurrency primitives for agent loop
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),

        // Logging
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),

        // Retry logic and circuit breaker (production-tested)
        .package(url: "https://github.com/CorvidLabs/swift-retry", from: "0.1.0"),

        // AgentRunKit - Production agent SDK (OpenAI, Anthropic, Gemini, MLX)
        // Works on macOS 26 - will migrate to Foundation Models in iOS 27 (September)
        .package(url: "https://github.com/Tom-Ryder/AgentRunKit.git", from: "5.3.0"),

        // OpenAI for embeddings only (AgentRunKit handles LLM)
        .package(url: "https://github.com/MacPaw/OpenAI", branch: "main"),
    ],
    targets: [
        // RAG: VectorStore protocol, document loaders, retrievers
        .target(
            name: "AgentRAG",
            dependencies: [
                // SQLiteVec made optional - use InMemoryVectorStore instead
                // .product(name: "SQLiteVec", package: "SQLiteVec"),
                .product(name: "OpenAI", package: "OpenAI"),  // For embeddings
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // Tools: Memory tools using AgentRunKit + our VectorStore
        .target(name: "AgentTools", dependencies: [
            "AgentRAG",
            .product(name: "AgentRunKit", package: "AgentRunKit"),
        ]),

        // Chains: AgentRunKit wrappers + builders
        .target(
            name: "AgentChains",
            dependencies: [
                "AgentTools", "AgentRAG",
                .product(name: "AgentRunKit", package: "AgentRunKit"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        .testTarget(
            name: "SwiftAgentsTests",
            dependencies: ["AgentRAG", "AgentTools", "AgentChains"]
        ),
    ]
)
