// AgentTools/GitTools.swift
// Git operations for autonomous agents

import Foundation
import AgentRunKit

// MARK: - Git Status Tool

/// Parameters for git status
public struct GitStatusParams: Codable, Sendable, SchemaProviding {
    /// Repository path (defaults to current directory)
    public let path: String?

    /// Show untracked files
    public let showUntracked: Bool?

    public init(path: String? = nil, showUntracked: Bool? = nil) {
        self.path = path
        self.showUntracked = showUntracked
    }
}

/// Create git status tool
public func createGitStatusTool<C: ToolContext>() throws -> Tool<GitStatusParams, String, C> {
    try Tool(
        name: "git_status",
        description: """
        Get git repository status.

        Use this to:
        - Check for uncommitted changes
        - See staged files
        - List untracked files
        - Check current branch
        """
    ) { params, _ in
        let repoPath = (params.path ?? ".") as NSString
        let expandedPath = repoPath.expandingTildeInPath

        var args = ["status", "--short", "--branch"]
        if params.showUntracked ?? true {
            args.append("--untracked-files=all")
        }

        let result = try executeGitCommand(args: args, workingDir: expandedPath)

        if result.exitCode != 0 {
            return "❌ Git Error: \(result.stderr)"
        }

        var output = "🔀 Git Status\n"
        output += "Repository: \(expandedPath)\n\n"

        if result.stdout.isEmpty {
            output += "✅ Working tree clean\n"
        } else {
            output += result.stdout
        }

        return output
    }
}

// MARK: - Git Diff Tool

/// Parameters for git diff
public struct GitDiffParams: Codable, Sendable, SchemaProviding {
    /// Repository path
    public let path: String?

    /// Show staged changes instead of unstaged
    public let staged: Bool?

    /// Specific file to diff
    public let file: String?

    public init(path: String? = nil, staged: Bool? = nil, file: String? = nil) {
        self.path = path
        self.staged = staged
        self.file = file
    }
}

/// Create git diff tool
public func createGitDiffTool<C: ToolContext>() throws -> Tool<GitDiffParams, String, C> {
    try Tool(
        name: "git_diff",
        description: """
        Show git diff of changes.

        Use this to:
        - Review uncommitted changes
        - Check staged changes
        - Compare specific files
        - See what will be committed
        """
    ) { params, _ in
        let repoPath = (params.path ?? ".") as NSString
        let expandedPath = repoPath.expandingTildeInPath

        var args = ["diff"]
        if params.staged ?? false {
            args.append("--staged")
        }
        if let file = params.file {
            args.append(file)
        }

        let result = try executeGitCommand(args: args, workingDir: expandedPath)

        if result.exitCode != 0 {
            return "❌ Git Error: \(result.stderr)"
        }

        if result.stdout.isEmpty {
            return "📝 No changes to show"
        }

        var output = "📝 Git Diff\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += result.stdout

        return output
    }
}

// MARK: - Git Commit Tool

/// Parameters for git commit
public struct GitCommitParams: Codable, Sendable, SchemaProviding {
    /// Commit message
    public let message: String

    /// Repository path
    public let path: String?

    /// Files to stage and commit (if empty, commits all staged files)
    public let files: [String]?

    /// Add all changes before committing
    public let addAll: Bool?

    public init(message: String, path: String? = nil, files: [String]? = nil, addAll: Bool? = nil) {
        self.message = message
        self.path = path
        self.files = files
        self.addAll = addAll
    }
}

/// Create git commit tool
public func createGitCommitTool<C: ToolContext>() throws -> Tool<GitCommitParams, String, C> {
    try Tool(
        name: "git_commit",
        description: """
        Create a git commit.

        Use this to:
        - Commit staged changes
        - Commit specific files
        - Save work with meaningful messages

        ⚠️ Important: Only commits files that are staged or specified.
        Use git_add first to stage files.
        """
    ) { params, _ in
        let repoPath = (params.path ?? ".") as NSString
        let expandedPath = repoPath.expandingTildeInPath

        // Add files if specified
        if params.addAll ?? false {
            let addResult = try executeGitCommand(args: ["add", "."], workingDir: expandedPath)
            if addResult.exitCode != 0 {
                return "❌ Git Add Error: \(addResult.stderr)"
            }
        } else if let files = params.files {
            for file in files {
                let addResult = try executeGitCommand(args: ["add", file], workingDir: expandedPath)
                if addResult.exitCode != 0 {
                    return "❌ Git Add Error for \(file): \(addResult.stderr)"
                }
            }
        }

        // Commit
        let result = try executeGitCommand(
            args: ["commit", "-m", params.message],
            workingDir: expandedPath
        )

        if result.exitCode != 0 {
            return "❌ Git Commit Error: \(result.stderr)"
        }

        return """
        ✅ Git Commit Successful

        Message: \(params.message)

        \(result.stdout)
        """
    }
}

// MARK: - Git Log Tool

/// Parameters for git log
public struct GitLogParams: Codable, Sendable, SchemaProviding {
    /// Repository path
    public let path: String?

    /// Number of commits to show
    public let count: Int?

    /// Show one line per commit
    public let oneline: Bool?

    public init(path: String? = nil, count: Int? = nil, oneline: Bool? = nil) {
        self.path = path
        self.count = count
        self.oneline = oneline
    }
}

/// Create git log tool
public func createGitLogTool<C: ToolContext>() throws -> Tool<GitLogParams, String, C> {
    try Tool(
        name: "git_log",
        description: """
        Show git commit history.

        Use this to:
        - Review recent commits
        - Check commit messages
        - See project history
        - Find specific commits
        """
    ) { params, _ in
        let repoPath = (params.path ?? ".") as NSString
        let expandedPath = repoPath.expandingTildeInPath

        var args = ["log"]

        if let count = params.count {
            args.append("-\(count)")
        } else {
            args.append("-10") // Default to last 10
        }

        if params.oneline ?? true {
            args.append("--oneline")
            args.append("--decorate")
        }

        let result = try executeGitCommand(args: args, workingDir: expandedPath)

        if result.exitCode != 0 {
            return "❌ Git Error: \(result.stderr)"
        }

        var output = "📜 Git Log\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += result.stdout

        return output
    }
}

// MARK: - Git Branch Tool

/// Parameters for git branch operations
public struct GitBranchParams: Codable, Sendable, SchemaProviding {
    /// Repository path
    public let path: String?

    /// List all branches
    public let list: Bool?

    /// Create new branch
    public let create: String?

    /// Switch to branch
    public let checkout: String?

    public init(path: String? = nil, list: Bool? = nil, create: String? = nil, checkout: String? = nil) {
        self.path = path
        self.list = list
        self.create = create
        self.checkout = checkout
    }
}

/// Create git branch tool
public func createGitBranchTool<C: ToolContext>() throws -> Tool<GitBranchParams, String, C> {
    try Tool(
        name: "git_branch",
        description: """
        Manage git branches.

        Use this to:
        - List branches
        - Create new branches
        - Switch branches
        - Check current branch
        """
    ) { params, _ in
        let repoPath = (params.path ?? ".") as NSString
        let expandedPath = repoPath.expandingTildeInPath

        // List branches
        if params.list ?? true {
            let result = try executeGitCommand(args: ["branch", "-a"], workingDir: expandedPath)
            if result.exitCode != 0 {
                return "❌ Git Error: \(result.stderr)"
            }

            var output = "🌿 Git Branches\n"
            output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            output += result.stdout
            return output
        }

        // Create branch
        if let branchName = params.create {
            let result = try executeGitCommand(args: ["branch", branchName], workingDir: expandedPath)
            if result.exitCode != 0 {
                return "❌ Git Error: \(result.stderr)"
            }
            return "✅ Created branch: \(branchName)"
        }

        // Checkout branch
        if let branchName = params.checkout {
            let result = try executeGitCommand(args: ["checkout", branchName], workingDir: expandedPath)
            if result.exitCode != 0 {
                return "❌ Git Error: \(result.stderr)"
            }
            return "✅ Switched to branch: \(branchName)\n\(result.stdout)"
        }

        return "❌ No operation specified"
    }
}

// MARK: - Git Clone Tool

/// Parameters for git clone
public struct GitCloneParams: Codable, Sendable, SchemaProviding {
    /// Repository URL to clone
    public let url: String

    /// Target directory (optional)
    public let directory: String?

    /// Clone depth (shallow clone)
    public let depth: Int?

    /// Clone single branch
    public let branch: String?

    public init(url: String, directory: String? = nil, depth: Int? = nil, branch: String? = nil) {
        self.url = url
        self.directory = directory
        self.depth = depth
        self.branch = branch
    }
}

/// Create git clone tool
public func createGitCloneTool<C: ToolContext>() throws -> Tool<GitCloneParams, String, C> {
    try Tool(
        name: "git_clone",
        description: """
        Clone a git repository.

        Use this to:
        - Clone GitHub/GitLab repos
        - Download open source projects
        - Get repository code

        Supports shallow clones and single branch clones for speed.
        """
    ) { params, _ in
        var args = ["clone"]

        if let depth = params.depth {
            args.append("--depth")
            args.append("\(depth)")
        }

        if let branch = params.branch {
            args.append("--branch")
            args.append(branch)
            args.append("--single-branch")
        }

        args.append(params.url)

        if let directory = params.directory {
            args.append(directory)
        }

        let result = try executeGitCommand(args: args, workingDir: FileManager.default.currentDirectoryPath)

        if result.exitCode != 0 {
            return "❌ Git Clone Error: \(result.stderr)"
        }

        return """
        ✅ Repository Cloned

        URL: \(params.url)
        \(result.stderr)
        """
    }
}

// MARK: - Git Helper

private func executeGitCommand(
    args: [String],
    workingDir: String
) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

    return (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
}
