// AgentTools/FileSystemTools.swift
// File system operations for autonomous agents

import Foundation
import AgentRunKit

// MARK: - File Read Tool

/// Parameters for reading files
public struct FileReadParams: Codable, Sendable, SchemaProviding {
    /// Path to the file to read
    public let path: String

    /// Maximum bytes to read (prevents loading huge files)
    public let maxBytes: Int?

    public init(path: String, maxBytes: Int? = nil) {
        self.path = path
        self.maxBytes = maxBytes
    }
}

/// Create file read tool
public func createFileReadTool<C: ToolContext>() throws -> Tool<FileReadParams, String, C> {
    try Tool(
        name: "read_file",
        description: """
        Read contents of a file from the file system.

        Use this to:
        - Read source code files
        - Check configuration files
        - Read logs or output files
        - Inspect data files

        The tool will automatically detect text vs binary files.
        For large files, only the first portion will be read.
        """
    ) { params, _ in
        let fileManager = FileManager.default
        let filePath = (params.path as NSString).expandingTildeInPath

        // Check if file exists
        guard fileManager.fileExists(atPath: filePath) else {
            return "❌ Error: File not found at '\(params.path)'"
        }

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return "❌ Error: '\(params.path)' is a directory, not a file. Use list_directory instead."
        }

        do {
            // Get file attributes
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            let fileSize = attributes[.size] as? UInt64 ?? 0

            // Read file data
            let maxBytes = params.maxBytes ?? 1_000_000 // 1MB default
            let data: Data

            if fileSize > maxBytes {
                // Read only first portion
                let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
                data = fileHandle.readData(ofLength: maxBytes)
                try fileHandle.close()
            } else {
                data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            }

            // Try to decode as text
            if let text = String(data: data, encoding: .utf8) {
                var output = "📄 File: \(params.path)\n"
                output += "Size: \(formatBytes(fileSize))\n"
                if fileSize > maxBytes {
                    output += "⚠️ Large file - showing first \(formatBytes(UInt64(maxBytes)))\n"
                }
                output += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
                output += text
                return output
            } else {
                return "📄 File: \(params.path)\n❌ Binary file (cannot display as text)\nSize: \(formatBytes(fileSize))"
            }
        } catch {
            return "❌ Error reading file: \(error.localizedDescription)"
        }
    }
}

// MARK: - File Write Tool

/// Parameters for writing files
public struct FileWriteParams: Codable, Sendable, SchemaProviding {
    /// Path where to write the file
    public let path: String

    /// Content to write
    public let content: String

    /// Create directories if they don't exist
    public let createDirectories: Bool?

    /// Append to existing file instead of overwriting
    public let append: Bool?

    public init(path: String, content: String, createDirectories: Bool? = nil, append: Bool? = nil) {
        self.path = path
        self.content = content
        self.createDirectories = createDirectories
        self.append = append
    }
}

/// Create file write tool
public func createFileWriteTool<C: ToolContext>() throws -> Tool<FileWriteParams, String, C> {
    try Tool(
        name: "write_file",
        description: """
        Write content to a file.

        Use this to:
        - Create new files
        - Overwrite existing files
        - Append to existing files
        - Save generated code or data

        The tool can automatically create parent directories if needed.
        """
    ) { params, _ in
        let fileManager = FileManager.default
        let filePath = (params.path as NSString).expandingTildeInPath
        let createDirs = params.createDirectories ?? true
        let append = params.append ?? false

        do {
            // Create parent directories if needed
            if createDirs {
                let directory = (filePath as NSString).deletingLastPathComponent
                try fileManager.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            // Write or append content
            if append && fileManager.fileExists(atPath: filePath) {
                let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
                fileHandle.seekToEndOfFile()
                fileHandle.write(params.content.data(using: .utf8)!)
                try fileHandle.close()

                return """
                ✅ File Updated: \(params.path)
                Mode: Appended
                Content Length: \(params.content.count) characters
                """
            } else {
                try params.content.write(
                    toFile: filePath,
                    atomically: true,
                    encoding: .utf8
                )

                return """
                ✅ File Written: \(params.path)
                Mode: \(fileManager.fileExists(atPath: filePath) ? "Overwritten" : "Created")
                Content Length: \(params.content.count) characters
                """
            }
        } catch {
            return "❌ Error writing file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Directory List Tool

/// Parameters for listing directory contents
public struct ListDirectoryParams: Codable, Sendable, SchemaProviding {
    /// Path to directory
    public let path: String

    /// Include hidden files (starting with .)
    public let includeHidden: Bool?

    /// Show file sizes and permissions
    public let detailed: Bool?

    public init(path: String, includeHidden: Bool? = nil, detailed: Bool? = nil) {
        self.path = path
        self.includeHidden = includeHidden
        self.detailed = detailed
    }
}

/// Create directory listing tool
public func createListDirectoryTool<C: ToolContext>() throws -> Tool<ListDirectoryParams, String, C> {
    try Tool(
        name: "list_directory",
        description: """
        List contents of a directory.

        Use this to:
        - Explore file system structure
        - Find files in a directory
        - Check what files exist
        - Navigate the project structure
        """
    ) { params, _ in
        let fileManager = FileManager.default
        let dirPath = (params.path as NSString).expandingTildeInPath
        let includeHidden = params.includeHidden ?? false
        let detailed = params.detailed ?? false

        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dirPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return "❌ Error: Directory not found at '\(params.path)'"
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: dirPath)
            let filtered = includeHidden ? contents : contents.filter { !$0.hasPrefix(".") }

            var output = "📁 Directory: \(params.path)\n"
            output += "Items: \(filtered.count)\n\n"

            if filtered.isEmpty {
                output += "(empty)\n"
                return output
            }

            // Sort: directories first, then files
            let sorted = filtered.sorted { item1, item2 in
                let path1 = (dirPath as NSString).appendingPathComponent(item1)
                let path2 = (dirPath as NSString).appendingPathComponent(item2)

                var isDir1: ObjCBool = false
                var isDir2: ObjCBool = false
                fileManager.fileExists(atPath: path1, isDirectory: &isDir1)
                fileManager.fileExists(atPath: path2, isDirectory: &isDir2)

                if isDir1.boolValue != isDir2.boolValue {
                    return isDir1.boolValue
                }
                return item1 < item2
            }

            for item in sorted {
                let itemPath = (dirPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)

                if detailed {
                    let attributes = try? fileManager.attributesOfItem(atPath: itemPath)
                    let size = attributes?[.size] as? UInt64 ?? 0
                    let icon = isDir.boolValue ? "📁" : "📄"

                    output += "\(icon) \(item)"
                    if !isDir.boolValue {
                        output += " (\(formatBytes(size)))"
                    }
                    output += "\n"
                } else {
                    let icon = isDir.boolValue ? "📁" : "📄"
                    output += "\(icon) \(item)\n"
                }
            }

            return output
        } catch {
            return "❌ Error listing directory: \(error.localizedDescription)"
        }
    }
}

// MARK: - File Delete Tool

/// Parameters for deleting files/directories
public struct FileDeleteParams: Codable, Sendable, SchemaProviding {
    /// Path to file or directory to delete
    public let path: String

    /// Allow deleting directories (safety check)
    public let allowDirectory: Bool?

    public init(path: String, allowDirectory: Bool? = nil) {
        self.path = path
        self.allowDirectory = allowDirectory
    }
}

/// Create file deletion tool
public func createFileDeleteTool<C: ToolContext>() throws -> Tool<FileDeleteParams, String, C> {
    try Tool(
        name: "delete_file",
        description: """
        Delete a file or directory.

        Use this to:
        - Remove temporary files
        - Clean up generated files
        - Delete unwanted files

        ⚠️ Safety features:
        - Requires explicit permission to delete directories
        - Cannot delete system directories
        - Permanently deletes files (no trash/recovery)
        """
    ) { params, _ in
        let fileManager = FileManager.default
        let filePath = (params.path as NSString).expandingTildeInPath

        // Check if exists
        guard fileManager.fileExists(atPath: filePath) else {
            return "❌ Error: Path not found at '\(params.path)'"
        }

        // Check if directory
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)

        if isDirectory.boolValue && !(params.allowDirectory ?? false) {
            return """
            ⚠️ Error: '\(params.path)' is a directory.
            Set allowDirectory: true to delete directories.
            """
        }

        // Safety check - don't delete critical system paths
        let criticalPaths = ["/", "/bin", "/usr", "/System", "/Library", "/Applications"]
        if criticalPaths.contains(filePath) || filePath.hasPrefix("/System/") {
            return "⚠️ Error: Cannot delete system directory '\(params.path)'"
        }

        do {
            try fileManager.removeItem(atPath: filePath)
            let type = isDirectory.boolValue ? "Directory" : "File"
            return "✅ \(type) Deleted: \(params.path)"
        } catch {
            return "❌ Error deleting: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Functions

private func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}
