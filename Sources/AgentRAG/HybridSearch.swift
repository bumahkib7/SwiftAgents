// AgentRAG/HybridSearch.swift
// Hybrid search combining keyword (TF-IDF) + semantic (vector) search
// Uses Reciprocal Rank Fusion (RRF) to combine results - 2026 production standard

import Foundation

/// Hybrid search combining keyword and semantic search with RRF fusion
public struct HybridSearch {

    /// Keyword search result with TF-IDF scoring
    public struct KeywordResult: Sendable {
        public let id: String
        public let score: Double  // TF-IDF score
        public let matchedTerms: [String]

        public init(id: String, score: Double, matchedTerms: [String]) {
            self.id = id
            self.score = score
            self.matchedTerms = matchedTerms
        }
    }

    /// Efficient TF-IDF scorer with pre-computed term frequencies
    /// Complexity: O(n) init, O(n*q) search where n=docs, q=unique query terms
    public struct TFIDFScorer {
        private struct DocData {
            let id: String
            let termFreq: [String: Double]  // Pre-computed TF for O(1) lookup
            let termCount: Int
        }

        private let documents: [DocData]
        private let idf: [String: Double]  // Inverse document frequency

        public init(documents: [(id: String, text: String)]) {
            // Pre-compute term frequencies and IDF in single pass
            var termDocCount: [String: Int] = [:]
            let totalDocs = Double(documents.count)

            // Build efficient doc data structures with pre-computed TF
            self.documents = documents.map { doc in
                let terms = Self.tokenize(doc.text)
                let termCount = terms.count

                // Pre-compute term frequency dictionary for O(1) lookup
                var termFreq: [String: Double] = [:]
                var termOccurrences: [String: Int] = [:]

                for term in terms {
                    termOccurrences[term, default: 0] += 1
                }

                for (term, count) in termOccurrences {
                    termFreq[term] = Double(count) / Double(termCount)
                    termDocCount[term, default: 0] += 1
                }

                return DocData(id: doc.id, termFreq: termFreq, termCount: termCount)
            }

            // Calculate IDF: log(N / df) - pre-computed for all terms
            self.idf = termDocCount.mapValues { docCount in
                log(totalDocs / Double(docCount))
            }
        }

        /// Tokenize text into terms (lowercase, alphanumeric only)
        private static func tokenize(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }  // Filter out single characters
        }

        /// Efficient search with pre-computed TF and O(1) term lookups
        public func search(query: String, topK: Int = 10) -> [KeywordResult] {
            let queryTerms = Set(Self.tokenize(query))  // Use Set to avoid duplicates
            guard !queryTerms.isEmpty else { return [] }

            var scores: [(id: String, score: Double, matchedTerms: [String])] = []
            scores.reserveCapacity(documents.count)  // Pre-allocate for efficiency

            for doc in documents {
                var docScore = 0.0
                var matchedTerms: [String] = []
                matchedTerms.reserveCapacity(queryTerms.count)

                for queryTerm in queryTerms {
                    // O(1) lookup for pre-computed TF
                    guard let tf = doc.termFreq[queryTerm] else { continue }

                    // O(1) lookup for IDF
                    let idfScore = idf[queryTerm] ?? 0.0

                    // TF-IDF score
                    let termScore = tf * idfScore

                    if termScore > 0 {
                        docScore += termScore
                        matchedTerms.append(queryTerm)
                    }
                }

                if docScore > 0 {
                    scores.append((id: doc.id, score: docScore, matchedTerms: matchedTerms))
                }
            }

            // Efficient partial sort - only sort top K
            if scores.count > topK {
                scores = Array(scores.sorted { $0.score > $1.score }.prefix(topK))
            } else {
                scores.sort { $0.score > $1.score }
            }

            return scores.map { KeywordResult(id: $0.id, score: $0.score, matchedTerms: $0.matchedTerms) }
        }
    }

    /// Reciprocal Rank Fusion (RRF) - combines ranked lists
    /// Paper: "Reciprocal Rank Fusion outperforms Condorcet and individual Rank Learning Methods"
    /// Standard k value in 2026: 60
    public static func reciprocalRankFusion(
        keywordResults: [KeywordResult],
        semanticResults: [(id: String, score: Double)],
        k: Int = 60
    ) -> [(id: String, score: Double)] {

        var rrfScores: [String: Double] = [:]

        // Add keyword rankings
        for (rank, result) in keywordResults.enumerated() {
            let rankScore = 1.0 / Double(k + rank + 1)
            rrfScores[result.id, default: 0.0] += rankScore
        }

        // Add semantic rankings
        for (rank, result) in semanticResults.enumerated() {
            let rankScore = 1.0 / Double(k + rank + 1)
            rrfScores[result.id, default: 0.0] += rankScore
        }

        // Sort by RRF score descending
        return rrfScores.map { (id: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }
    }

    /// Normalize company names for fuzzy matching
    /// "adesso SE" → "adesso", "Deutsche Bank AG" → "deutsche bank"
    public static func normalizeCompanyName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " se", with: "")
            .replacingOccurrences(of: " ag", with: "")
            .replacingOccurrences(of: " gmbh", with: "")
            .replacingOccurrences(of: " kg", with: "")
            .replacingOccurrences(of: " co", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
