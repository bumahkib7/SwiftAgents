// AgentRAG/SQLiteVecStore.swift
// Vector database implementation using SQLiteVec
// Persistent memory for agents with semantic search

import Foundation
import SQLiteVec
import Logging

/// SQLite-based vector store with persistent storage
public actor SQLiteVecStore: VectorStore {
    private let db: Database
    private let dimensions: Int
    private let tableName: String
    private let logger: Logger

    /// Initialize vector store
    /// - Parameters:
    ///   - path: Database file path (nil for in-memory)
    ///   - dimensions: Vector dimensions (must match embedding model)
    ///   - tableName: Table name for vectors
    ///   - logger: Logger instance
    public init(
        path: String? = nil,
        dimensions: Int,
        tableName: String = "vectors",
        logger: Logger = Logger(label: "SQLiteVecStore")
    ) throws {
        // Initialize SQLiteVec library
        try SQLiteVec.initialize()

        // Create database
        if let path = path {
            self.db = try Database(.uri("file://\(path)"))
        } else {
            self.db = try Database(.inMemory)
        }

        self.dimensions = dimensions
        self.tableName = tableName
        self.logger = logger

        logger.info("Initialized SQLiteVecStore: \(dimensions) dims, table=\(tableName)")
    }

    /// Initialize tables (call this after creating the store)
    public func setup() async throws {
        try await createTable()
        logger.debug("Setup complete")
    }

    private func createTable() async throws {
        // Create virtual table for vectors
        let createVectorTable = """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(tableName) USING vec0(
            embedding float[\(dimensions)]
        )
        """

        // Create metadata table
        let createMetadataTable = """
        CREATE TABLE IF NOT EXISTS \(tableName)_metadata (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            timestamp REAL NOT NULL,
            tags TEXT,  -- JSON array
            custom_data TEXT  -- JSON object
        )
        """

        try await db.execute(createVectorTable)
        try await db.execute(createMetadataTable)

        logger.debug("Tables created: \(tableName), \(tableName)_metadata")
    }

    public func insert(embedding: [Double], metadata: VectorMetadata) async throws {
        guard embedding.count == dimensions else {
            throw VectorStoreError.invalidDimensions(expected: dimensions, got: embedding.count)
        }

        // Convert Double to Float for SQLiteVec
        let floatEmbedding = embedding.map { Float($0) }

        // Encode metadata as JSON
        let tagsJSON = try JSONSerialization.data(withJSONObject: metadata.tags)
        let customDataJSON = try JSONSerialization.data(withJSONObject: metadata.customData)

        // Insert into metadata table
        try await db.execute(
            """
            INSERT OR REPLACE INTO \(tableName)_metadata (id, text, timestamp, tags, custom_data)
            VALUES (?, ?, ?, ?, ?)
            """,
            params: [
                metadata.id,
                metadata.text,
                metadata.timestamp.timeIntervalSince1970,
                String(data: tagsJSON, encoding: .utf8) ?? "[]",
                String(data: customDataJSON, encoding: .utf8) ?? "{}"
            ]
        )

        // Get or calculate rowid from metadata ID hash
        let rowId = abs(metadata.id.hashValue)

        // Insert into vector table
        try await db.execute(
            """
            INSERT OR REPLACE INTO \(tableName) (rowid, embedding)
            VALUES (?, ?)
            """,
            params: [rowId, floatEmbedding]
        )

        logger.debug("Inserted vector: id=\(metadata.id), dims=\(embedding.count)")
    }

    public func search(
        embedding: [Double],
        topK: Int,
        minSimilarity: Double,
        filter: (@Sendable (VectorMetadata) -> Bool)?
    ) async throws -> [SearchResult] {
        guard embedding.count == dimensions else {
            throw VectorStoreError.invalidDimensions(expected: dimensions, got: embedding.count)
        }

        // Convert Double to Float for query
        let floatEmbedding = embedding.map { Float($0) }

        // Query vectors by distance (L2 distance)
        let results = try await db.query(
            """
            SELECT
                v.rowid,
                v.distance,
                m.id,
                m.text,
                m.timestamp,
                m.tags,
                m.custom_data
            FROM \(tableName) v
            JOIN \(tableName)_metadata m ON abs(m.id) = v.rowid
            WHERE v.embedding MATCH ?
            ORDER BY v.distance
            LIMIT ?
            """,
            params: [floatEmbedding, topK * 2]  // Fetch 2x for filtering
        )

        // Parse results
        var searchResults: [SearchResult] = []

        for row in results {
            guard let id = row["id"] as? String,
                  let text = row["text"] as? String,
                  let timestampInterval = row["timestamp"] as? Double,
                  let tagsJSON = row["tags"] as? String,
                  let customDataJSON = row["custom_data"] as? String,
                  let distance = row["distance"] as? Double
            else {
                continue
            }

            // Parse JSON metadata
            let tags = (try? JSONSerialization.jsonObject(with: Data(tagsJSON.utf8)) as? [String]) ?? []
            let customData = (try? JSONSerialization.jsonObject(with: Data(customDataJSON.utf8)) as? [String: String]) ?? [:]

            let metadata = VectorMetadata(
                id: id,
                text: text,
                timestamp: Date(timeIntervalSince1970: timestampInterval),
                tags: tags,
                customData: customData
            )

            // Apply filter if provided
            if let filter = filter, !filter(metadata) {
                continue
            }

            // Convert L2 distance to cosine similarity approximation
            // For normalized vectors: similarity ≈ 1 - (distance² / 2)
            // For unnormalized: fetch embedding and calculate exact cosine
            let similarity = max(0.0, 1.0 - (distance * distance / 2.0))

            // Skip if below threshold
            if similarity < minSimilarity {
                continue
            }

            searchResults.append(SearchResult(
                metadata: metadata,
                embedding: embedding,  // Store query embedding (fetch actual if needed)
                similarity: similarity
            ))

            // Stop once we have enough results
            if searchResults.count >= topK {
                break
            }
        }

        logger.debug("Search complete: \(searchResults.count) results (topK=\(topK))")

        return searchResults
    }

    public func delete(id: String) async throws {
        let rowId = abs(id.hashValue)

        try await db.execute("DELETE FROM \(tableName) WHERE rowid = ?", params: [rowId])
        try await db.execute("DELETE FROM \(tableName)_metadata WHERE id = ?", params: [id])

        logger.debug("Deleted vector: id=\(id)")
    }

    public func deleteAll(where filter: @escaping @Sendable (VectorMetadata) -> Bool) async throws -> Int {
        // Fetch all metadata
        let results = try await db.query("SELECT id, text, timestamp, tags, custom_data FROM \(tableName)_metadata")

        var deletedCount = 0

        for row in results {
            guard let id = row["id"] as? String,
                  let text = row["text"] as? String,
                  let timestampInterval = row["timestamp"] as? Double,
                  let tagsJSON = row["tags"] as? String,
                  let customDataJSON = row["custom_data"] as? String
            else {
                continue
            }

            let tags = (try? JSONSerialization.jsonObject(with: Data(tagsJSON.utf8)) as? [String]) ?? []
            let customData = (try? JSONSerialization.jsonObject(with: Data(customDataJSON.utf8)) as? [String: String]) ?? [:]

            let metadata = VectorMetadata(
                id: id,
                text: text,
                timestamp: Date(timeIntervalSince1970: timestampInterval),
                tags: tags,
                customData: customData
            )

            if filter(metadata) {
                try await delete(id: id)
                deletedCount += 1
            }
        }

        logger.info("Deleted \(deletedCount) vectors matching filter")

        return deletedCount
    }

    public func clear() async throws {
        try await db.execute("DELETE FROM \(tableName)")
        try await db.execute("DELETE FROM \(tableName)_metadata")

        logger.info("Cleared all vectors")
    }

    public func count() async throws -> Int {
        let results = try await db.query("SELECT COUNT(*) as count FROM \(tableName)_metadata")
        guard let first = results.first, let count = first["count"] as? Int else {
            return 0
        }
        return count
    }
}
