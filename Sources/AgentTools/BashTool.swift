// AgentTools/BashTool.swift
// Terminal command execution for autonomous agents
// Security: Commands run in user context, no sudo/elevated privileges

import Foundation
import AgentRunKit

// MARK: - Bash Tool Parameters

/// Parameters for bash command execution
public struct BashParams: Codable, Sendable, SchemaProviding {
    /// The bash command to execute
    public let command: String

    /// Working directory (defaults to current directory)
    public let workingDirectory: String?

    /// Environment variables to set
    public let environment: [String: String]?

    /// Timeout in seconds (max 60s)
    public let timeout: Int?

    public init(
        command: String,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: Int? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}

/// Result of bash command execution
public struct BashResult: Codable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let executionTime: Double

    public init(stdout: String, stderr: String, exitCode: Int32, executionTime: Double) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.executionTime = executionTime
    }
}

// MARK: - Bash Tool

/// Create bash command execution tool
public func createBashTool<C: ToolContext>() throws -> Tool<BashParams, String, C> {
    try Tool(
        name: "bash",
        description: """
        Execute bash/shell commands in the terminal.

        Use this to:
        - Run system commands (ls, cat, grep, find, etc.)
        - Execute scripts and programs
        - Check file system state
        - Install packages or dependencies
        - Automate system tasks

        Security notes:
        - Commands run with current user permissions
        - No sudo or elevated privileges
        - 60 second timeout maximum
        - Dangerous commands (rm -rf /, etc.) should be confirmed first

        Examples:
        - "ls -la" - list directory contents
        - "git status" - check git repository status
        - "python script.py" - run Python script
        - "npm install" - install Node.js packages
        """
    ) { params, _ in
        // Validate timeout
        let timeout = params.timeout ?? 30
        guard timeout > 0 && timeout <= 60 else {
            return "❌ Error: timeout must be between 1-60 seconds"
        }

        // Validate command is not empty
        guard !params.command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "❌ Error: command cannot be empty"
        }

        // Warn about dangerous commands
        let dangerous = ["rm -rf /", "dd if=", "mkfs", ":(){ :|:& };:"]
        if dangerous.contains(where: { params.command.contains($0) }) {
            return "⚠️ Error: Dangerous command detected. This tool cannot execute potentially destructive commands."
        }

        let startTime = Date()

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", params.command]

        // Set working directory
        if let workingDir = params.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }

        // Set environment
        if let env = params.environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        // Capture output
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Execute with timeout
        do {
            try process.run()

            // Wait with timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            // Get output
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus
            let executionTime = Date().timeIntervalSince(startTime)

            // Format result
            var output = "🖥️  Bash Command Executed\n\n"
            output += "Command: \(params.command)\n"
            output += "Exit Code: \(exitCode)\n"
            output += "Execution Time: \(String(format: "%.2f", executionTime))s\n\n"

            if !stdout.isEmpty {
                output += "📤 STDOUT:\n"
                output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                output += stdout
                if !stdout.hasSuffix("\n") { output += "\n" }
                output += "\n"
            }

            if !stderr.isEmpty {
                output += "📛 STDERR:\n"
                output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                output += stderr
                if !stderr.hasSuffix("\n") { output += "\n" }
                output += "\n"
            }

            if exitCode != 0 {
                output += "⚠️ Command failed with exit code \(exitCode)\n"
            }

            return output

        } catch {
            return "❌ Error executing command: \(error.localizedDescription)"
        }
    }
}
