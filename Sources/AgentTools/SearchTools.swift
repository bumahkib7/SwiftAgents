// AgentTools/SearchTools.swift
// Advanced file and content search tools for autonomous agents

import Foundation
import AgentRunKit

// MARK: - Grep Tool (Content Search)

/// Parameters for grep-like content search
public struct GrepParams: Codable, Sendable, SchemaProviding {
    /// Pattern to search for (supports regex)
    public let pattern: String

    /// Path to search in (file or directory)
    public let path: String

    /// Use regex instead of literal string
    public let regex: Bool?

    /// Case insensitive search
    public let ignoreCase: Bool?

    /// Search recursively in directories
    public let recursive: Bool?

    /// Show line numbers
    public let lineNumbers: Bool?

    /// Show context lines (before/after match)
    public let context: Int?

    /// File patterns to include (e.g., "*.swift")
    public let include: String?

    /// File patterns to exclude (e.g., "*.git/*")
    public let exclude: String?

    public init(
        pattern: String,
        path: String = ".",
        regex: Bool? = nil,
        ignoreCase: Bool? = nil,
        recursive: Bool? = nil,
        lineNumbers: Bool? = nil,
        context: Int? = nil,
        include: String? = nil,
        exclude: String? = nil
    ) {
        self.pattern = pattern
        self.path = path
        self.regex = regex
        self.ignoreCase = ignoreCase
        self.recursive = recursive
        self.lineNumbers = lineNumbers
        self.context = context
        self.include = include
        self.exclude = exclude
    }
}

/// Create grep tool for content search
public func createGrepTool<C: ToolContext>() throws -> Tool<GrepParams, String, C> {
    try Tool(
        name: "grep",
        description: """
        Search for patterns in files (like grep/ripgrep).

        Use this to:
        - Find code references
        - Search for text patterns
        - Locate specific strings in files
        - Search with regex patterns
        - Search across entire codebase

        Examples:
        - grep("TODO", path: ".", recursive: true) - find all TODOs
        - grep("func.*async", path: "src", regex: true) - find async functions
        - grep("import React", path: ".", include: "*.tsx") - find React imports
        """
    ) { params, _ in
        let searchPath = (params.path as NSString).expandingTildeInPath
        let recursive = params.recursive ?? true
        let ignoreCase = params.ignoreCase ?? false
        let showLineNumbers = params.lineNumbers ?? true
        let contextLines = params.context ?? 0
        let useRegex = params.regex ?? false

        var results: [(file: String, line: Int, content: String)] = []
        let fileManager = FileManager.default

        // Build regex or literal pattern
        let searchOptions: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        let regex: NSRegularExpression?

        if useRegex {
            do {
                regex = try NSRegularExpression(pattern: params.pattern, options: searchOptions)
            } catch {
                return "❌ Error: Invalid regex pattern - \(error.localizedDescription)"
            }
        } else {
            // Escape special regex characters for literal search
            let escaped = NSRegularExpression.escapedPattern(for: params.pattern)
            regex = try? NSRegularExpression(pattern: escaped, options: searchOptions)
        }

        guard let searchRegex = regex else {
            return "❌ Error: Failed to create search pattern"
        }

        // Search function
        func searchFile(at path: String) {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if searchRegex.firstMatch(in: line, range: range) != nil {
                    results.append((file: path, line: index + 1, content: line))
                }
            }
        }

        // Traverse directory
        func traverse(path: String) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return }

            // Skip excluded patterns
            if let exclude = params.exclude {
                let filename = (path as NSString).lastPathComponent
                if filename.range(of: exclude, options: .regularExpression) != nil {
                    return
                }
            }

            if isDirectory.boolValue {
                if recursive {
                    guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }
                    for item in contents {
                        // Skip hidden files and common ignore patterns
                        if item.hasPrefix(".") || item == "node_modules" || item == "Pods" { continue }
                        let itemPath = (path as NSString).appendingPathComponent(item)
                        traverse(path: itemPath)
                    }
                }
            } else {
                // Check include pattern
                if let include = params.include {
                    let filename = (path as NSString).lastPathComponent
                    if filename.range(of: include.replacingOccurrences(of: "*", with: ".*"), options: .regularExpression) == nil {
                        return
                    }
                }
                searchFile(at: path)
            }
        }

        // Start search
        traverse(path: searchPath)

        // Format results
        if results.isEmpty {
            return "🔍 No matches found for '\(params.pattern)' in \(params.path)"
        }

        var output = "🔍 Search Results: '\(params.pattern)'\n"
        output += "Found \(results.count) match\(results.count == 1 ? "" : "es")\n\n"

        // Limit to first 100 matches to avoid huge output
        let limited = Array(results.prefix(100))
        var currentFile = ""

        for result in limited {
            if result.file != currentFile {
                currentFile = result.file
                output += "\n📄 \(result.file)\n"
                output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            }

            if showLineNumbers {
                output += "\(result.line): "
            }
            output += "\(result.content.trimmingCharacters(in: .whitespaces))\n"
        }

        if results.count > 100 {
            output += "\n⚠️ Showing first 100 of \(results.count) matches\n"
        }

        return output
    }
}

// MARK: - Glob Tool (File Pattern Search)

/// Parameters for glob file pattern search
public struct GlobParams: Codable, Sendable, SchemaProviding {
    /// Glob pattern (e.g., "**/*.swift", "src/**/*.ts")
    public let pattern: String

    /// Base directory to search from
    public let baseDirectory: String?

    /// Maximum results to return
    public let limit: Int?

    public init(pattern: String, baseDirectory: String? = nil, limit: Int? = nil) {
        self.pattern = pattern
        self.baseDirectory = baseDirectory
        self.limit = limit
    }
}

/// Create glob tool for file pattern matching
public func createGlobTool<C: ToolContext>() throws -> Tool<GlobParams, String, C> {
    try Tool(
        name: "glob",
        description: """
        Find files matching glob patterns.

        Use this to:
        - Find all files of a type (*.swift, *.tsx)
        - Search nested directories (**/test/*.py)
        - Locate specific file patterns
        - Explore project structure

        Pattern syntax:
        - * matches anything except /
        - ** matches anything including /
        - ? matches single character
        - [abc] matches a, b, or c

        Examples:
        - "**/*.swift" - all Swift files
        - "src/**/*.test.ts" - all test files in src
        - "*.{js,ts}" - all JS or TS files
        """
    ) { params, _ in
        let basePath = (params.baseDirectory ?? ".") as NSString
        let expandedBase = basePath.expandingTildeInPath
        let fileManager = FileManager.default

        var matches: [String] = []

        // Convert glob pattern to regex
        func globToRegex(_ pattern: String) -> NSRegularExpression? {
            var regex = pattern
            regex = regex.replacingOccurrences(of: ".", with: "\\.")
            regex = regex.replacingOccurrences(of: "**/", with: "(.*/)?")
            regex = regex.replacingOccurrences(of: "**", with: ".*")
            regex = regex.replacingOccurrences(of: "*", with: "[^/]*")
            regex = regex.replacingOccurrences(of: "?", with: "[^/]")
            return try? NSRegularExpression(pattern: "^\(regex)$")
        }

        guard let regex = globToRegex(params.pattern) else {
            return "❌ Error: Invalid glob pattern"
        }

        // Recursive search
        func search(in directory: String, relativePath: String = "") {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else { return }

            for item in contents {
                // Skip hidden and ignored
                if item.hasPrefix(".") || item == "node_modules" || item == "Pods" || item == ".build" {
                    continue
                }

                let fullPath = (directory as NSString).appendingPathComponent(item)
                let relPath = relativePath.isEmpty ? item : "\(relativePath)/\(item)"

                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)

                // Check if matches pattern
                let range = NSRange(relPath.startIndex..., in: relPath)
                if regex.firstMatch(in: relPath, range: range) != nil {
                    matches.append(relPath)
                }

                // Recurse into directories
                if isDirectory.boolValue {
                    search(in: fullPath, relativePath: relPath)
                }

                // Check limit
                if let limit = params.limit, matches.count >= limit {
                    return
                }
            }
        }

        search(in: expandedBase)

        // Format output
        if matches.isEmpty {
            return "📂 No files match pattern '\(params.pattern)'"
        }

        var output = "📂 Files matching '\(params.pattern)'\n"
        output += "Found \(matches.count) file\(matches.count == 1 ? "" : "s")\n\n"

        for match in matches.sorted() {
            output += "📄 \(match)\n"
        }

        if let limit = params.limit, matches.count >= limit {
            output += "\n⚠️ Limit reached (\(limit) files)\n"
        }

        return output
    }
}

// MARK: - Find Tool (Advanced File Search)

/// Parameters for find command
public struct FindParams: Codable, Sendable, SchemaProviding {
    /// Directory to search in
    public let path: String

    /// File name pattern
    public let name: String?

    /// File type (file, directory)
    public let type: String?

    /// Modified within last N days
    public let modifiedDays: Int?

    /// File size filter (e.g., ">1M", "<100K")
    public let size: String?

    /// Maximum depth to search
    public let maxDepth: Int?

    public init(
        path: String = ".",
        name: String? = nil,
        type: String? = nil,
        modifiedDays: Int? = nil,
        size: String? = nil,
        maxDepth: Int? = nil
    ) {
        self.path = path
        self.name = name
        self.type = type
        self.modifiedDays = modifiedDays
        self.size = size
        self.maxDepth = maxDepth
    }
}

/// Create find tool for advanced file search
public func createFindTool<C: ToolContext>() throws -> Tool<FindParams, String, C> {
    try Tool(
        name: "find",
        description: """
        Advanced file search with filters.

        Use this to:
        - Find files by name, size, date
        - Search with depth limits
        - Filter by file type
        - Find recently modified files

        Examples:
        - find(name: "*.log", modifiedDays: 7) - recent log files
        - find(type: "directory", maxDepth: 2) - shallow dir search
        - find(name: "package.json") - find all package.json
        """
    ) { params, _ in
        let searchPath = (params.path as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        var results: [(path: String, info: String)] = []

        func search(in path: String, depth: Int) {
            // Check max depth
            if let maxDepth = params.maxDepth, depth > maxDepth {
                return
            }

            guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }

            for item in contents {
                if item.hasPrefix(".") { continue }

                let itemPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory)

                // Check type filter
                if let typeFilter = params.type {
                    if typeFilter == "directory" && !isDirectory.boolValue { continue }
                    if typeFilter == "file" && isDirectory.boolValue { continue }
                }

                // Check name filter
                if let namePattern = params.name {
                    let pattern = namePattern.replacingOccurrences(of: "*", with: ".*")
                    if item.range(of: pattern, options: .regularExpression) == nil {
                        if isDirectory.boolValue {
                            search(in: itemPath, depth: depth + 1)
                        }
                        continue
                    }
                }

                // Check modification date
                if let modDays = params.modifiedDays {
                    if let attrs = try? fileManager.attributesOfItem(atPath: itemPath),
                       let modDate = attrs[.modificationDate] as? Date {
                        let daysSince = -modDate.timeIntervalSinceNow / 86400
                        if daysSince > Double(modDays) { continue }
                    }
                }

                // Get file info
                var info = ""
                if let attrs = try? fileManager.attributesOfItem(atPath: itemPath) {
                    if let size = attrs[.size] as? UInt64 {
                        info = formatBytes(size)
                    }
                }

                results.append((path: itemPath, info: info))

                // Recurse
                if isDirectory.boolValue {
                    search(in: itemPath, depth: depth + 1)
                }
            }
        }

        search(in: searchPath, depth: 0)

        if results.isEmpty {
            return "🔍 No files found matching criteria"
        }

        var output = "🔍 Find Results\n"
        output += "Found \(results.count) item\(results.count == 1 ? "" : "s")\n\n"

        for result in results.prefix(200) {
            let relativePath = result.path.replacingOccurrences(of: searchPath + "/", with: "")
            output += "📄 \(relativePath)"
            if !result.info.isEmpty {
                output += " (\(result.info))"
            }
            output += "\n"
        }

        if results.count > 200 {
            output += "\n⚠️ Showing first 200 of \(results.count) results\n"
        }

        return output
    }
}

// MARK: - Helper Functions

private func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}
