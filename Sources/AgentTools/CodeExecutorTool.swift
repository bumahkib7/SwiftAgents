// AgentTools/CodeExecutorTool.swift
// Sandboxed code execution for autonomous agents

import Foundation
import AgentRunKit

// MARK: - Code Executor Parameters

/// Supported programming languages for code execution
public enum ProgrammingLanguage: String, Sendable {
    case python
    case swift
    case javascript
    case bash
    case ruby
}

// MARK: - Custom Codable Implementation for Case-Insensitive Decoding

extension ProgrammingLanguage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle empty string (schema inference testing) - default to python
        guard !rawValue.isEmpty else {
            self = .python
            return
        }

        // Case-insensitive matching
        let lowercased = rawValue.lowercased()

        switch lowercased {
        case "python", "py":
            self = .python
        case "swift":
            self = .swift
        case "javascript", "js", "node":
            self = .javascript
        case "bash", "sh", "shell":
            self = .bash
        case "ruby", "rb":
            self = .ruby
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid programming language: '\(rawValue)'. Supported: python, swift, javascript, bash, ruby"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// Parameters for code execution
public struct CodeExecuteParams: Codable, Sendable, SchemaProviding {
    /// Programming language
    public let language: ProgrammingLanguage

    /// Code to execute
    public let code: String

    /// Working directory
    public let workingDirectory: String?

    /// Timeout in seconds (max 30s for code execution)
    public let timeout: Int?

    public init(
        language: ProgrammingLanguage,
        code: String,
        workingDirectory: String? = nil,
        timeout: Int? = nil
    ) {
        self.language = language
        self.code = code
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }

    // MARK: - Explicit JSON Schema for AgentRunKit

    public static var jsonSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "language": [
                    "type": "string",
                    "enum": ["python", "swift", "javascript", "bash", "ruby"],
                    "description": "Programming language (case-insensitive). Aliases: py, js, node, sh, shell, rb"
                ],
                "code": [
                    "type": "string",
                    "description": "Code to execute"
                ],
                "workingDirectory": [
                    "type": "string",
                    "description": "Working directory (optional)"
                ],
                "timeout": [
                    "type": "integer",
                    "description": "Timeout in seconds (max 30, optional)"
                ]
            ],
            "required": ["language", "code"]
        ]
    }
}

// MARK: - Code Executor Tool

/// Create code executor tool
public func createCodeExecutorTool<C: ToolContext>() throws -> Tool<CodeExecuteParams, String, C> {
    try Tool(
        name: "execute_code",
        description: """
        Execute code in a sandboxed environment.

        Supported languages:
        - Python: Run Python scripts
        - Swift: Run Swift code (requires Swift installed)
        - JavaScript: Run Node.js code
        - Bash: Run shell scripts
        - Ruby: Run Ruby scripts

        Use this to:
        - Test code snippets
        - Run data processing scripts
        - Validate algorithms
        - Perform calculations
        - Generate outputs

        Security:
        - 30 second timeout maximum
        - Runs in user context (no elevated privileges)
        - No network access restrictions
        - File system access same as user
        """
    ) { params, _ in
        let timeout = min(params.timeout ?? 30, 30)

        // Validate code is not empty
        guard !params.code.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "❌ Error: code cannot be empty"
        }

        let startTime = Date()

        do {
            let result: (stdout: String, stderr: String, exitCode: Int32)

            switch params.language {
            case .python:
                result = try executePython(code: params.code, workingDir: params.workingDirectory, timeout: timeout)

            case .swift:
                result = try executeSwift(code: params.code, workingDir: params.workingDirectory, timeout: timeout)

            case .javascript:
                result = try executeJavaScript(code: params.code, workingDir: params.workingDirectory, timeout: timeout)

            case .bash:
                result = try executeBash(code: params.code, workingDir: params.workingDirectory, timeout: timeout)

            case .ruby:
                result = try executeRuby(code: params.code, workingDir: params.workingDirectory, timeout: timeout)
            }

            let executionTime = Date().timeIntervalSince(startTime)

            // Format result
            var output = "💻 Code Executed\n\n"
            output += "Language: \(params.language.rawValue)\n"
            output += "Exit Code: \(result.exitCode)\n"
            output += "Execution Time: \(String(format: "%.2f", executionTime))s\n\n"

            if !result.stdout.isEmpty {
                output += "📤 OUTPUT:\n"
                output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                output += result.stdout
                if !result.stdout.hasSuffix("\n") { output += "\n" }
                output += "\n"
            }

            if !result.stderr.isEmpty {
                output += "📛 ERRORS:\n"
                output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                output += result.stderr
                if !result.stderr.hasSuffix("\n") { output += "\n" }
                output += "\n"
            }

            if result.exitCode != 0 {
                output += "⚠️ Execution failed with exit code \(result.exitCode)\n"
            }

            return output

        } catch {
            return "❌ Error executing code: \(error.localizedDescription)"
        }
    }
}

// MARK: - Language-Specific Executors

private func executePython(
    code: String,
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    // Write code to temporary file
    let tempFile = NSTemporaryDirectory() + "swift_agents_\(UUID().uuidString).py"
    try code.write(toFile: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tempFile) }

    return try executeCommand(
        executable: "/usr/bin/python3",
        arguments: [tempFile],
        workingDir: workingDir,
        timeout: timeout
    )
}

private func executeSwift(
    code: String,
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    // Write code to temporary file
    let tempFile = NSTemporaryDirectory() + "swift_agents_\(UUID().uuidString).swift"
    try code.write(toFile: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tempFile) }

    return try executeCommand(
        executable: "/usr/bin/swift",
        arguments: [tempFile],
        workingDir: workingDir,
        timeout: timeout
    )
}

private func executeJavaScript(
    code: String,
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    // Write code to temporary file
    let tempFile = NSTemporaryDirectory() + "swift_agents_\(UUID().uuidString).js"
    try code.write(toFile: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tempFile) }

    return try executeCommand(
        executable: "/usr/bin/node",
        arguments: [tempFile],
        workingDir: workingDir,
        timeout: timeout
    )
}

private func executeBash(
    code: String,
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    return try executeCommand(
        executable: "/bin/bash",
        arguments: ["-c", code],
        workingDir: workingDir,
        timeout: timeout
    )
}

private func executeRuby(
    code: String,
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    // Write code to temporary file
    let tempFile = NSTemporaryDirectory() + "swift_agents_\(UUID().uuidString).rb"
    try code.write(toFile: tempFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: tempFile) }

    return try executeCommand(
        executable: "/usr/bin/ruby",
        arguments: [tempFile],
        workingDir: workingDir,
        timeout: timeout
    )
}

// MARK: - Process Executor

private func executeCommand(
    executable: String,
    arguments: [String],
    workingDir: String?,
    timeout: Int
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    if let workingDir = workingDir {
        process.currentDirectoryURL = URL(fileURLWithPath: (workingDir as NSString).expandingTildeInPath)
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Timeout handling
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
        if process.isRunning {
            process.terminate()
        }
    }

    process.waitUntilExit()
    timeoutTask.cancel()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    let exitCode = process.terminationStatus

    return (stdout: stdout, stderr: stderr, exitCode: exitCode)
}
