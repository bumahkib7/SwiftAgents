# SwiftAgents

A pure Swift agent framework for building AI assistants with tool use, memory, and RAG.

**Backend-agnostic:** Works with Anthropic Claude, OpenAI, or local models through a unified protocol.

## Installation

```swift
dependencies: [
    .package(url: "file:///path/to/SwiftAgents", from: "1.0.0")
]
```

## Quick Start

### 1. Create a Tool

```swift
import AgentTools

struct ProjectAnalyzerTool: AgentTool {
    let name = "analyze_project"
    let description = "Analyzes a codebase structure and identifies key files"

    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "Path to the project root"
            ],
            "language": [
                "type": "string",
                "description": "Primary programming language"
            ]
        ],
        "required": ["project_path"]
    ]

    func execute(parameters: [String: Any]) async throws -> String {
        guard let path = parameters["project_path"] as? String else {
            throw ToolError.invalidParameters("Missing project_path")
        }

        // Scan directory
        let url = URL(fileURLWithPath: path)
        let files = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )

        // Identify key files
        let services = files.filter { $0.lastPathComponent.contains("Service") }
        let controllers = files.filter { $0.lastPathComponent.contains("Controller") }
        let configs = files.filter { $0.lastPathComponent.contains("config") }

        return """
        Project Analysis:
        - Total files: \(files.count)
        - Service files: \(services.count)
        - Controller files: \(controllers.count)
        - Config files: \(configs.count)

        Key files:
        \(services.map { "- " + $0.lastPathComponent }.joined(separator: "\n"))
        """
    }
}
```

### 2. Create an Agent

```swift
import AgentCore
import AgentTools
import AgentChains

// Setup backend
let backend = AnthropicBackend(
    apiKey: "your-api-key",
    model: "claude-sonnet-4.6-20260620"
)

// Create session
let session = LanguageModelSession(backend: backend)

// Register tools
let toolRegistry = ToolRegistry()
toolRegistry.register(ProjectAnalyzerTool())
toolRegistry.register(WebSearchTool())
toolRegistry.register(FileReaderTool())

// Create agent
let agent = ReActAgent(
    session: session,
    toolRegistry: toolRegistry,
    maxIterations: 10
)

// Run task
let result = try await agent.run(
    task: """
    I have a Kotlin project at /path/to/vyda-user-sync.
    Implement user authentication with JWT.

    Steps:
    1. Analyze the project structure
    2. Search the web for best practices
    3. Identify which files to modify
    4. Provide step-by-step implementation plan with code
    """,
    extendedThinking: true  // Let Claude plan with extended thinking
)

print(result)
```

## Architecture

### AgentCore
- `LanguageModelBackend` - Protocol for any LLM backend
- `AnthropicBackend` - Anthropic Claude API implementation
- `LanguageModelSession` - Manages conversation state
- Supports extended thinking mode for complex reasoning

### AgentTools
- `AgentTool` - Protocol for tools
- `ToolRegistry` - Manages and executes tools
- Built-in tools: Web search, file operations, code analysis

### AgentChains
- `ReActAgent` - Reasoning + Acting loop
- Iteratively: Think → Use Tools → Observe → Repeat
- Stops when task is complete or max iterations reached

### AgentMemory
- Conversation buffer with windowing
- Summary/compression strategies
- Session persistence

### AgentRAG
- Vector store integration (SQLiteVec)
- Document loaders and chunkers
- Semantic search retrievers

### AgentObservability
- Structured logging
- Tracing hooks for debugging
- Cost tracking per session

## Extended Thinking Mode

Claude Sonnet 4.6+ supports extended thinking for complex tasks:

```swift
let response = try await agent.run(
    task: "Design a complete authentication system",
    extendedThinking: true  // Claude will plan deeply before acting
)
```

## Tool Best Practices

### Make Tools Focused
```swift
// ❌ Bad: One tool does everything
struct MegaTool: AgentTool {
    func execute(parameters: [String: Any]) async throws -> String {
        // 1000 lines of code doing 10 different things
    }
}

// ✅ Good: Each tool does one thing well
struct AnalyzeProjectTool: AgentTool { /* ... */ }
struct ReadFileTool: AgentTool { /* ... */ }
struct SearchWebTool: AgentTool { /* ... */ }
```

### Provide Clear Descriptions
The LLM uses these to decide which tool to call:

```swift
let description = """
Analyzes a codebase structure and returns:
- File count and organization
- Detected frameworks and dependencies
- Key files (services, controllers, models)
- Recommended files to modify for common tasks
"""
```

### Return Structured Results
```swift
return """
## Project: vyda-user-sync

**Language:** Kotlin
**Framework:** Spring Boot + Gradle

**Structure:**
- Services: 12 files
- Controllers: 8 files
- Repositories: 6 files

**Key Files for Auth:**
1. `UserService.kt` - extend this for user management
2. `build.gradle.kts` - add Spring Security dependency
3. `application.yml` - configure JWT settings
"""
```

## Roadmap

- [x] Core agent loop (ReAct)
- [x] Anthropic backend
- [x] Tool system
- [ ] OpenAI backend
- [ ] Memory management
- [ ] RAG integration
- [ ] Streaming support
- [ ] Apple LanguageModel backend (when macOS 27 GA)
- [ ] Observability/tracing

## License

MIT
