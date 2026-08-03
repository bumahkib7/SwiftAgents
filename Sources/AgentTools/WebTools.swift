// AgentTools/WebTools.swift
// Web fetching and HTTP requests for autonomous agents

import Foundation
import AgentRunKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Web Fetch Tool

/// Parameters for fetching web content
public struct WebFetchParams: Codable, Sendable, SchemaProviding {
    /// URL to fetch
    public let url: String

    /// HTTP method (GET, POST, etc.)
    public let method: String?

    /// HTTP headers
    public let headers: [String: String]?

    /// Request body (for POST/PUT)
    public let body: String?

    /// Timeout in seconds
    public let timeout: Int?

    public init(
        url: String,
        method: String? = nil,
        headers: [String: String]? = nil,
        body: String? = nil,
        timeout: Int? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// Create web fetch tool
@available(iOS 13.0, *)
public func createWebFetchTool<C: ToolContext>() throws -> Tool<WebFetchParams, String, C> {
    try Tool(
        name: "fetch_url",
        description: """
        Fetch content from a URL via HTTP/HTTPS.

        Use this to:
        - Download web pages
        - Call REST APIs
        - Fetch data from web services
        - Download files
        - Make HTTP requests

        Supports:
        - GET, POST, PUT, DELETE, PATCH methods
        - Custom headers
        - Request body for POST/PUT
        - JSON and text responses
        """
    ) { params, _ in
        // Validate URL
        guard let url = URL(string: params.url) else {
            return "❌ Error: Invalid URL '\(params.url)'"
        }

        let timeout = TimeInterval(params.timeout ?? 30)

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = params.method?.uppercased() ?? "GET"

        // Add headers
        if let headers = params.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add body
        if let body = params.body {
            request.httpBody = body.data(using: .utf8)
        }

        // Execute request
        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: "❌ Error: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(returning: "❌ Error: Invalid response")
                    return
                }

                guard let data = data else {
                    continuation.resume(returning: "❌ Error: No data received")
                    return
                }

                // Format response
                var output = "🌐 HTTP Response\n\n"
                output += "URL: \(params.url)\n"
                output += "Method: \(request.httpMethod ?? "GET")\n"
                output += "Status: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\n"
                output += "Content-Length: \(data.count) bytes\n\n"

                // Show headers if useful
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    output += "Content-Type: \(contentType)\n\n"
                }

                // Try to decode response
                if let text = String(data: data, encoding: .utf8) {
                    output += "📄 RESPONSE BODY:\n"
                    output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

                    // Try to format JSON for readability
                    if let jsonData = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
                       let prettyJson = String(data: prettyData, encoding: .utf8) {
                        output += prettyJson
                    } else {
                        output += text
                    }

                    if !text.hasSuffix("\n") { output += "\n" }
                } else {
                    output += "📄 Binary data (\(data.count) bytes)\n"
                }

                if httpResponse.statusCode >= 400 {
                    output += "\n⚠️ HTTP error: \(httpResponse.statusCode)\n"
                }

                continuation.resume(returning: output)
            }

            task.resume()
        }
    }
}

// MARK: - HTTP Request Tool (Advanced)

/// Parameters for advanced HTTP requests
public struct HttpRequestParams: Codable, Sendable, SchemaProviding {
    /// URL to request
    public let url: String

    /// HTTP method
    public let method: String

    /// Query parameters
    public let queryParams: [String: String]?

    /// HTTP headers
    public let headers: [String: String]?

    /// JSON body (will be serialized)
    public let jsonBody: [String: String]?

    /// Form data (application/x-www-form-urlencoded)
    public let formData: [String: String]?

    public init(
        url: String,
        method: String = "GET",
        queryParams: [String: String]? = nil,
        headers: [String: String]? = nil,
        jsonBody: [String: String]? = nil,
        formData: [String: String]? = nil
    ) {
        self.url = url
        self.method = method
        self.queryParams = queryParams
        self.headers = headers
        self.jsonBody = jsonBody
        self.formData = formData
    }
}

/// Create advanced HTTP request tool
public func createHttpRequestTool<C: ToolContext>() throws -> Tool<HttpRequestParams, String, C> {
    try Tool(
        name: "http_request",
        description: """
        Make advanced HTTP requests with JSON/form data support.

        Use this to:
        - Call REST APIs with JSON payloads
        - Submit form data
        - Add query parameters
        - Make authenticated requests

        Automatically handles:
        - JSON serialization
        - Form encoding
        - Query parameter encoding
        - Content-Type headers
        """
    ) { params, _ in
        // Build URL with query parameters
        var urlComponents = URLComponents(string: params.url)

        if let queryParams = params.queryParams {
            urlComponents?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents?.url else {
            return "❌ Error: Invalid URL '\(params.url)'"
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = params.method.uppercased()

        // Add headers
        if let headers = params.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add body
        if let jsonBody = params.jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: jsonBody)
        } else if let formData = params.formData {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let formString = formData.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = formString.data(using: .utf8)
        }

        // Execute request (same as fetch_url)
        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: "❌ Error: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      let data = data else {
                    continuation.resume(returning: "❌ Error: Invalid response")
                    return
                }

                var output = "🌐 HTTP Response\n\n"
                output += "URL: \(url.absoluteString)\n"
                output += "Method: \(params.method.uppercased())\n"
                output += "Status: \(httpResponse.statusCode)\n\n"

                if let text = String(data: data, encoding: .utf8) {
                    if let jsonData = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
                       let prettyJson = String(data: prettyData, encoding: .utf8) {
                        output += prettyJson
                    } else {
                        output += text
                    }
                } else {
                    output += "Binary data (\(data.count) bytes)"
                }

                continuation.resume(returning: output)
            }

            task.resume()
        }
    }
}
