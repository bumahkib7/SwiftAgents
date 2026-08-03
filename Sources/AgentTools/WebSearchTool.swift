// AgentTools/WebSearchTool.swift
// Web search using DuckDuckGo API for autonomous agents

import Foundation
import AgentRunKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Web Search Tool

/// Parameters for web search
public struct WebSearchParams: Codable, Sendable, SchemaProviding {
    /// Search query
    public let query: String

    /// Number of results (1-20)
    public let maxResults: Int?

    /// Region for search (e.g., "us-en", "de-de")
    public let region: String?

    public init(query: String, maxResults: Int? = nil, region: String? = nil) {
        self.query = query
        self.maxResults = maxResults
        self.region = region
    }
}

/// Search result
public struct SearchResult: Codable {
    public let title: String
    public let url: String
    public let snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Create web search tool using DuckDuckGo
public func createWebSearchTool<C: ToolContext>() throws -> Tool<WebSearchParams, String, C> {
    try Tool(
        name: "web_search",
        description: """
        Search the web using DuckDuckGo.

        Use this to:
        - Find current information
        - Research topics
        - Look up documentation
        - Find solutions to problems
        - Get latest news

        Returns titles, URLs, and snippets of search results.

        Examples:
        - web_search("Swift async await tutorial")
        - web_search("latest iOS release notes")
        - web_search("how to fix memory leak in Python")
        """
    ) { params, _ in
        let maxResults = min(params.maxResults ?? 10, 20)

        // Use DuckDuckGo Instant Answer API (free, no key required)
        let query = params.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let region = params.region ?? "wt-wt"

        // DuckDuckGo HTML search (we'll parse it)
        let searchURL = "https://html.duckduckgo.com/html/?q=\(query)&kl=\(region)"

        guard let url = URL(string: searchURL) else {
            return "❌ Error: Invalid search URL"
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: "❌ Search Error: \(error.localizedDescription)")
                    return
                }

                guard let data = data,
                      let html = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: "❌ Error: No search results")
                    return
                }

                // Parse HTML results (basic parsing)
                let results = parseDuckDuckGoResults(html: html, maxResults: maxResults)

                if results.isEmpty {
                    continuation.resume(returning: "🔍 No results found for '\(params.query)'")
                    return
                }

                var output = "🔍 Web Search Results\n"
                output += "Query: \"\(params.query)\"\n"
                output += "Found \(results.count) result\(results.count == 1 ? "" : "s")\n\n"

                for (index, result) in results.enumerated() {
                    output += "[\(index + 1)] \(result.title)\n"
                    output += "🔗 \(result.url)\n"
                    output += "\(result.snippet)\n\n"
                }

                continuation.resume(returning: output)
            }

            task.resume()
        }
    }
}

// MARK: - Alternative: Brave Search API

/// Parameters for Brave search (requires API key)
public struct BraveSearchParams: Codable, Sendable, SchemaProviding {
    /// Search query
    public let query: String

    /// Brave API key
    public let apiKey: String

    /// Number of results
    public let count: Int?

    public init(query: String, apiKey: String, count: Int? = nil) {
        self.query = query
        self.apiKey = apiKey
        self.count = count
    }
}

/// Create Brave Search tool (requires API key but more reliable)
@available(iOS 13.0, *)
public func createBraveSearchTool<C: ToolContext>() throws -> Tool<BraveSearchParams, String, C> {
    try Tool(
        name: "brave_search",
        description: """
        Search the web using Brave Search API.

        Requires: Brave Search API key (get free at brave.com/search/api)

        More reliable than DuckDuckGo, with:
        - Structured JSON results
        - Better ranking
        - More metadata

        Use for production search needs.
        """
    ) { params, _ in
        let count = min(params.count ?? 10, 20)
        let query = params.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let urlString = "https://api.search.brave.com/res/v1/web/search?q=\(query)&count=\(count)"
        guard let url = URL(string: urlString) else {
            return "❌ Error: Invalid search URL"
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(params.apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: "❌ Search Error: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(returning: "❌ Error: Invalid response")
                    return
                }

                if httpResponse.statusCode == 401 {
                    continuation.resume(returning: "❌ Error: Invalid API key")
                    return
                }

                guard let data = data else {
                    continuation.resume(returning: "❌ Error: No data received")
                    return
                }

                // Parse JSON response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let web = json["web"] as? [String: Any],
                      let results = web["results"] as? [[String: Any]] else {
                    continuation.resume(returning: "❌ Error: Invalid response format")
                    return
                }

                if results.isEmpty {
                    continuation.resume(returning: "🔍 No results found for '\(params.query)'")
                    return
                }

                var output = "🔍 Brave Search Results\n"
                output += "Query: \"\(params.query)\"\n"
                output += "Found \(results.count) result\(results.count == 1 ? "" : "s")\n\n"

                for (index, result) in results.enumerated() {
                    let title = result["title"] as? String ?? "No title"
                    let url = result["url"] as? String ?? ""
                    let description = result["description"] as? String ?? ""

                    output += "[\(index + 1)] \(title)\n"
                    output += "🔗 \(url)\n"
                    output += "\(description)\n\n"
                }

                continuation.resume(returning: output)
            }

            task.resume()
        }
    }
}

// MARK: - HTML Parser (Basic)

private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [SearchResult] {
    var results: [SearchResult] = []

    // Very basic HTML parsing (regex-based - not robust but works for DDG)
    let resultPattern = #"<div class="result__body">[\s\S]*?<a.*?href="(.*?)".*?class="result__a">(.*?)</a>[\s\S]*?<a.*?class="result__snippet">(.*?)</a>"#

    guard let regex = try? NSRegularExpression(pattern: resultPattern) else {
        return []
    }

    let range = NSRange(html.startIndex..., in: html)
    let matches = regex.matches(in: html, range: range)

    for match in matches.prefix(maxResults) {
        if match.numberOfRanges >= 4 {
            let urlRange = match.range(at: 1)
            let titleRange = match.range(at: 2)
            let snippetRange = match.range(at: 3)

            if let urlNSRange = Range(urlRange, in: html),
               let titleNSRange = Range(titleRange, in: html),
               let snippetNSRange = Range(snippetRange, in: html) {

                var url = String(html[urlNSRange])
                let title = String(html[titleNSRange]).stripHTMLTags()
                let snippet = String(html[snippetNSRange]).stripHTMLTags()

                // Clean URL (DDG uses redirects)
                if url.hasPrefix("//duckduckgo.com/l/?uddg=") {
                    if let decoded = url.components(separatedBy: "uddg=").last?
                        .removingPercentEncoding {
                        url = decoded
                    }
                }

                results.append(SearchResult(
                    title: title,
                    url: url,
                    snippet: snippet
                ))
            }
        }
    }

    return results
}

// MARK: - String Extensions

private extension String {
    func stripHTMLTags() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
