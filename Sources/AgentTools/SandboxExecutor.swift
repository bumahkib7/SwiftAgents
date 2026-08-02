// AgentTools/SandboxExecutor.swift
// Safe command execution sandbox with permission system
// Allows reading files, searching code, and other safe operations
// Blocks destructive operations or asks for confirmation

import Foundation
import Logging

// MARK: - Permission System

public enum CommandPermission {
    case allowed
    case needsConfirmation(reason: String)
    case blocked(reason: String)
}

public typealias PermissionHandler = @Sendable (String, String) async -> Bool

// MARK: - Sandbox Executor

/// Safely executes shell commands in a sandboxed environment
public actor SandboxExecutor {
    private let workingDirectory: URL
    private let logger: Logger
    private let permissionHandler: PermissionHandler?

    // Safe commands that don't modify files
    private let safeCommands: Set<String> = [
        "ls", "cat", "head", "tail", "grep", "find", "wc",
        "file", "stat", "pwd", "echo", "which", "tree",
        "rg", "ag", "ack"  // ripgrep, ag, ack for code search
    ]

    // Dangerous commands that are blocked
    private let blockedCommands: Set<String> = [
        "rm", "rmdir", "dd", "mkfs", "fdisk",
        "kill", "killall", "sudo", "su", "chmod", "chown",
        "mv", ">", ">>"  // Prevent redirects (pipes are allowed for grep, cat, etc.)
    ]

    public init(
        workingDirectory: URL,
        permissionHandler: PermissionHandler? = nil,
        logger: Logger = Logger(label: "SandboxExecutor")
    ) {
        self.workingDirectory = workingDirectory
        self.permissionHandler = permissionHandler
        self.logger = logger
    }

    /// Execute a command safely
    public func execute(command: String) async throws -> ExecutionResult {
        logger.info("Executing: \(command)")

        // Check permissions
        let permission = checkPermission(command: command)

        switch permission {
        case .allowed:
            break

        case .needsConfirmation(let reason):
            logger.warning("Command needs confirmation: \(reason)")

            if let handler = permissionHandler {
                let approved = await handler(command, reason)
                if !approved {
                    throw SandboxError.permissionDenied("User denied: \(reason)")
                }
            } else {
                throw SandboxError.permissionDenied("No permission handler configured")
            }

        case .blocked(let reason):
            logger.error("Command blocked: \(reason)")
            throw SandboxError.commandBlocked(reason)
        }

        // Execute
        return try await executeUnsafe(command: command)
    }

    // MARK: - Permission Checking

    private func checkPermission(command: String) -> CommandPermission {
        let components = command.split(separator: " ").map(String.init)
        guard let firstCommand = components.first else {
            return .blocked(reason: "Empty command")
        }

        // Extract base command (remove path)
        let baseCommand = URL(fileURLWithPath: firstCommand).lastPathComponent

        // Check blocked list - but be smart about context
        for blocked in blockedCommands {
            if command.contains(blocked) {
                // Special case: ">" and ">>" are only dangerous when writing to files
                // If used in grep patterns like "grep '>'" it's safe
                if blocked == ">" || blocked == ">>" {
                    // Check if it's in a quoted string (safe) or actual redirection (dangerous)
                    if command.contains("'\(blocked)'") || command.contains("\"\(blocked)\"") {
                        continue  // It's in quotes, safe
                    }
                    return .blocked(reason: "Contains file redirection: \(blocked)")
                }

                return .blocked(reason: "Contains dangerous command: \(blocked)")
            }
        }

        // Check safe list
        if safeCommands.contains(baseCommand) {
            return .allowed
        }

        // Unknown command - needs confirmation
        return .needsConfirmation(reason: "Unknown command: \(baseCommand)")
    }

    // MARK: - Execution

    private func executeUnsafe(command: String) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let startTime = Date()

        try process.run()

        // Wait with timeout (30 seconds)
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(30))
            if process.isRunning {
                process.terminate()
                logger.warning("Command timed out after 30s: \(command)")
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let duration = Date().timeIntervalSince(startTime)

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""
        let exitCode = Int(process.terminationStatus)

        logger.info("Command completed: exit=\(exitCode), duration=\(String(format: "%.2f", duration))s")

        return ExecutionResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            duration: duration
        )
    }
}

// MARK: - Result

public struct ExecutionResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public let duration: TimeInterval

    public var success: Bool {
        exitCode == 0
    }

    public var output: String {
        stdout.isEmpty ? stderr : stdout
    }
}

// MARK: - Errors

public enum SandboxError: Error, LocalizedError {
    case commandBlocked(String)
    case permissionDenied(String)
    case executionFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .commandBlocked(let reason):
            return "Command blocked: \(reason)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .timeout:
            return "Command timed out"
        }
    }
}
