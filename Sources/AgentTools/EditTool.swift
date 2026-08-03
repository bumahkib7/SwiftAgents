// AgentTools/EditTool.swift
// Smart file editing with find/replace for autonomous agents

import Foundation
import AgentRunKit

// MARK: - Edit Tool

/// Parameters for smart file editing
public struct EditParams: Codable, Sendable, SchemaProviding {
    /// Path to file to edit
    public let path: String

    /// Text to find and replace
    public let find: String

    /// Replacement text
    public let replace: String

    /// Replace all occurrences (default: false, replace first)
    public let replaceAll: Bool?

    /// Use regex for find pattern
    public let regex: Bool?

    /// Case insensitive search
    public let ignoreCase: Bool?

    /// Show preview without applying changes
    public let preview: Bool?

    public init(
        path: String,
        find: String,
        replace: String,
        replaceAll: Bool? = nil,
        regex: Bool? = nil,
        ignoreCase: Bool? = nil,
        preview: Bool? = nil
    ) {
        self.path = path
        self.find = find
        self.replace = replace
        self.replaceAll = replaceAll
        self.regex = regex
        self.ignoreCase = ignoreCase
        self.preview = preview
    }
}

/// Create edit tool for smart file editing
public func createEditTool<C: ToolContext>() throws -> Tool<EditParams, String, C> {
    try Tool(
        name: "edit_file",
        description: """
        Smart file editing with find and replace.

        Use this to:
        - Replace text in files
        - Refactor code
        - Update configuration
        - Fix typos or errors
        - Apply code changes

        Features:
        - Exact text matching or regex
        - Replace first or all occurrences
        - Preview changes before applying
        - Case sensitive/insensitive

        ⚠️ Important: The 'find' text must match EXACTLY (including whitespace).
        Use preview: true to check matches before applying.
        """
    ) { params, _ in
        let filePath = (params.path as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        // Check file exists
        guard fileManager.fileExists(atPath: filePath) else {
            return "❌ Error: File not found at '\(params.path)'"
        }

        // Read file
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return "❌ Error: Could not read file (binary or encoding issue)"
        }

        let useRegex = params.regex ?? false
        let replaceAll = params.replaceAll ?? false
        let ignoreCase = params.ignoreCase ?? false
        let preview = params.preview ?? false

        // Perform replacement
        let (newContent, replacementCount) = performReplacement(
            content: content,
            find: params.find,
            replace: params.replace,
            useRegex: useRegex,
            replaceAll: replaceAll,
            ignoreCase: ignoreCase
        )

        if replacementCount == 0 {
            return """
            ⚠️ No matches found

            File: \(params.path)
            Looking for: "\(params.find)"

            The text was not found in the file.
            Check:
            - Exact whitespace/indentation
            - Case sensitivity
            - Correct file
            """
        }

        // Preview mode
        if preview {
            let changes = highlightChanges(original: content, modified: newContent, find: params.find)
            return """
            👁️ Preview Mode - Changes NOT Applied

            File: \(params.path)
            Replacements: \(replacementCount)

            \(changes)

            To apply changes, set preview: false
            """
        }

        // Apply changes
        do {
            try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            return "❌ Error writing file: \(error.localizedDescription)"
        }

        // Show what changed
        let changes = highlightChanges(original: content, modified: newContent, find: params.find)

        return """
        ✅ File Edited Successfully

        File: \(params.path)
        Replacements: \(replacementCount)

        \(changes)
        """
    }
}

// MARK: - Multi-File Edit Tool

/// Parameters for editing multiple files
public struct MultiEditParams: Codable, Sendable, SchemaProviding {
    /// Glob pattern for files to edit
    public let pattern: String

    /// Text to find and replace
    public let find: String

    /// Replacement text
    public let replace: String

    /// Base directory
    public let baseDirectory: String?

    /// Preview without applying
    public let preview: Bool?

    public init(
        pattern: String,
        find: String,
        replace: String,
        baseDirectory: String? = nil,
        preview: Bool? = nil
    ) {
        self.pattern = pattern
        self.find = find
        self.replace = replace
        self.baseDirectory = baseDirectory
        self.preview = preview
    }
}

/// Create multi-file edit tool
public func createMultiEditTool<C: ToolContext>() throws -> Tool<MultiEditParams, String, C> {
    try Tool(
        name: "edit_files",
        description: """
        Edit multiple files matching a pattern.

        Use this to:
        - Refactor across codebase
        - Rename variables/functions
        - Update imports
        - Mass text replacement

        Example: edit_files(pattern: "**/*.swift", find: "oldName", replace: "newName")
        """
    ) { params, _ in
        let basePath = (params.baseDirectory ?? ".") as NSString
        let expandedBase = basePath.expandingTildeInPath
        let fileManager = FileManager.default
        let preview = params.preview ?? false

        // Find matching files (using similar logic to glob)
        var files: [String] = []
        func findFiles(in directory: String) {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
            for item in contents {
                if item.hasPrefix(".") || item == "node_modules" { continue }
                let fullPath = (directory as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)

                if isDirectory.boolValue {
                    findFiles(in: fullPath)
                } else {
                    // Simple pattern matching
                    let ext = (item as NSString).pathExtension
                    let patternExt = (params.pattern as NSString).pathExtension
                    if patternExt.isEmpty || ext == patternExt {
                        files.append(fullPath)
                    }
                }
            }
        }

        findFiles(in: expandedBase)

        var totalReplacements = 0
        var filesChanged = 0
        var output = ""

        for filePath in files {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (newContent, count) = performReplacement(
                content: content,
                find: params.find,
                replace: params.replace,
                useRegex: false,
                replaceAll: true,
                ignoreCase: false
            )

            if count > 0 {
                filesChanged += 1
                totalReplacements += count

                let relativePath = filePath.replacingOccurrences(of: expandedBase + "/", with: "")
                output += "\n📄 \(relativePath): \(count) replacement\(count == 1 ? "" : "s")\n"

                if !preview {
                    try? newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                }
            }
        }

        if filesChanged == 0 {
            return "⚠️ No matches found in \(files.count) files"
        }

        let status = preview ? "Preview Mode - NOT Applied" : "Applied"

        return """
        \(preview ? "👁️" : "✅") Multi-File Edit \(status)

        Pattern: \(params.pattern)
        Files changed: \(filesChanged)
        Total replacements: \(totalReplacements)
        \(output)
        """
    }
}

// MARK: - Helper Functions

private func performReplacement(
    content: String,
    find: String,
    replace: String,
    useRegex: Bool,
    replaceAll: Bool,
    ignoreCase: Bool
) -> (newContent: String, replacementCount: Int) {
    var count = 0

    if useRegex {
        // Regex replacement
        let options: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: find, options: options) else {
            return (content, 0)
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)
        count = matches.count

        if count == 0 {
            return (content, 0)
        }

        if replaceAll {
            let result = regex.stringByReplacingMatches(
                in: content,
                range: range,
                withTemplate: replace
            )
            return (result, count)
        } else {
            // Replace first match only
            let mutableString = NSMutableString(string: content)
            if let firstMatch = matches.first {
                regex.replaceMatches(
                    in: mutableString,
                    range: firstMatch.range,
                    withTemplate: replace
                )
            }
            return (mutableString as String, min(count, 1))
        }
    } else {
        // Literal text replacement
        let options: String.CompareOptions = ignoreCase ? [.caseInsensitive] : []

        if replaceAll {
            let result = content.replacingOccurrences(of: find, with: replace, options: options)
            count = (content.components(separatedBy: find).count - 1)
            return (result, count)
        } else {
            // Replace first occurrence
            if let range = content.range(of: find, options: options) {
                var result = content
                result.replaceSubrange(range, with: replace)
                return (result, 1)
            }
            return (content, 0)
        }
    }
}

private func highlightChanges(original: String, modified: String, find: String) -> String {
    let originalLines = original.components(separatedBy: .newlines)
    let modifiedLines = modified.components(separatedBy: .newlines)

    var output = "Changes:\n"
    output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

    // Show first few changes
    var changesShown = 0
    for (index, (oldLine, newLine)) in zip(originalLines, modifiedLines).enumerated() {
        if oldLine != newLine {
            output += "\nLine \(index + 1):\n"
            output += "- \(oldLine)\n"
            output += "+ \(newLine)\n"
            changesShown += 1

            if changesShown >= 5 {
                output += "\n... (showing first 5 changes)\n"
                break
            }
        }
    }

    return output
}
