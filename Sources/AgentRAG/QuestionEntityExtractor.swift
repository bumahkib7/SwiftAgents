// AgentRAG/QuestionEntityExtractor.swift
// Extract entities (companies, skills, dates) from user questions
// Enables metadata-filtered hybrid search in RAG systems

import Foundation

/// Extract searchable entities from natural language questions
public struct QuestionEntityExtractor {

    /// Extracted entities from a question
    public struct ExtractedEntities: Sendable {
        public let companies: [String]          // Detected company names
        public let normalizedCompanies: [String] // Lowercase, trimmed for matching
        public let skills: [String]             // Technical skills mentioned
        public let keywords: [String]           // Important keywords

        public init(companies: [String] = [], skills: [String] = [], keywords: [String] = []) {
            self.companies = companies
            self.normalizedCompanies = companies.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            self.skills = skills
            self.keywords = keywords
        }
    }

    /// Known company patterns to detect (expand this list as needed)
    private static let commonCompanyNames: Set<String> = [
        "adesso", "google", "amazon", "microsoft", "apple", "meta", "facebook",
        "netflix", "tesla", "spotify", "uber", "airbnb", "twitter", "linkedin",
        "ibm", "oracle", "sap", "salesforce", "adobe", "intel", "nvidia",
        "siemens", "bosch", "mercedes", "bmw", "volkswagen", "porsche",
        "allianz", "deutsche", "commerzbank", "infineon", "telekom"
    ]

    /// Common technical skills to detect
    private static let commonSkills: Set<String> = [
        "java", "python", "swift", "kotlin", "javascript", "typescript",
        "react", "angular", "vue", "node", "spring", "django", "flask",
        "docker", "kubernetes", "aws", "azure", "gcp", "terraform",
        "sql", "mongodb", "postgresql", "redis", "kafka", "elasticsearch",
        "git", "ci/cd", "agile", "scrum", "devops", "microservices"
    ]

    /// Extract entities from a question
    public static func extract(from question: String) -> ExtractedEntities {
        let lowercased = question.lowercased()
        let words = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }

        var detectedCompanies: [String] = []
        var detectedSkills: [String] = []
        var keywords: [String] = []

        // Detect company names
        for word in words {
            if commonCompanyNames.contains(word) {
                detectedCompanies.append(word)
            }
            if commonSkills.contains(word) {
                detectedSkills.append(word)
            }
        }

        // Extract multi-word company names (e.g., "Deutsche Bank", "Mercedes Benz")
        let multiWordPatterns = [
            ("deutsche", "bank"),
            ("mercedes", "benz"),
            ("deutsche", "telekom"),
            ("united", "health")
        ]

        for (word1, word2) in multiWordPatterns {
            if lowercased.contains("\(word1) \(word2)") {
                detectedCompanies.append("\(word1) \(word2)")
            }
        }

        // Extract important keywords (nouns, verbs related to work)
        let workKeywords: Set<String> = ["projekt", "project", "arbeit", "work", "rolle", "role", "aufgabe", "task"]
        for word in words where workKeywords.contains(word) {
            keywords.append(word)
        }

        return ExtractedEntities(
            companies: Array(Set(detectedCompanies)), // Remove duplicates
            skills: Array(Set(detectedSkills)),
            keywords: Array(Set(keywords))
        )
    }

    /// Create metadata filter for vector search based on extracted entities
    public static func createMetadataFilter(from entities: ExtractedEntities) -> ((VectorMetadata) -> Bool)? {
        // If no companies detected, don't filter
        guard !entities.normalizedCompanies.isEmpty else {
            return nil
        }

        // Return filter that matches any of the detected companies
        return { metadata in
            guard let companyData = metadata.customData["company_normalized"] else {
                return false // No company metadata - exclude
            }

            let metadataCompany = companyData.lowercased()

            // Check if any detected company matches
            return entities.normalizedCompanies.contains { detectedCompany in
                metadataCompany.contains(detectedCompany) || detectedCompany.contains(metadataCompany)
            }
        }
    }
}
