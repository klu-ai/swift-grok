import Vapor
import Foundation
import NIOFoundationCompat

/// Middleware that logs detailed information about requests and responses when verbose mode is enabled
struct VerboseLoggingMiddleware: AsyncMiddleware {
    let isEnabled: Bool
    
    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard isEnabled else {
            // If not enabled, just pass through to the next middleware
            return try await next.respond(to: request)
        }
        
        // Log the request details
        logRequest(request)
        
        // Get the response from the next middleware in the chain
        let response = try await next.respond(to: request)
        
        // Log the response details
        logResponse(response, for: request)
        
        return response
    }
    
    private func logRequest(_ request: Request) {
        let requestId = request.headers.first(name: "x-request-id") ?? request.id
        
        var requestLog = """
        
        ======== VERBOSE REQUEST [\(requestId)] ========
        \(request.method) \(request.url.path)
        Headers:
        """
        
        for (name, value) in request.headers {
            requestLog += "\n   \(name): \(value)"
        }
        
        // Try to log the body if possible
        if let contentType = request.headers.contentType,
           contentType.type == "application" && contentType.subType == "json" {
            // For JSON content
            if let bodyData = request.body.data,
               let bodyString = String(data: Data(buffer: bodyData), encoding: .utf8) {
                requestLog += "\nBody:\n\(prettyFormatJSON(bodyString))"
            } else {
                requestLog += "\nBody: <JSON content but unable to read>"
            }
        } else if let contentLength = request.headers.first(name: "content-length"),
                  let length = Int(contentLength) {
            requestLog += "\nBody: <\(length) bytes of data>"
        } else {
            requestLog += "\nBody: <none or streaming>"
        }
        
        requestLog += "\n========================================"
        
        request.logger.info("\(requestLog)")
    }
    
    private func logResponse(_ response: Response, for request: Request) {
        let requestId = request.headers.first(name: "x-request-id") ?? request.id
        
        var responseLog = """
        
        ======== VERBOSE RESPONSE [\(requestId)] ========
        Status: \(response.status)
        Headers:
        """
        
        for (name, value) in response.headers {
            responseLog += "\n   \(name): \(value)"
        }
        
        // Try to log the body if it's available
        if let contentType = response.headers.contentType,
           contentType.type == "application" && contentType.subType == "json" {
            // For JSON content
            if let bodyBuffer = response.body.data,
               let bodyString = String(data: bodyBuffer, encoding: .utf8) {
                responseLog += "\nBody:\n\(prettyFormatJSON(bodyString))"
            } else {
                responseLog += "\nBody: <JSON content but unable to read>"
            }
        } else if let contentLength = response.headers.first(name: "content-length"),
                  let length = Int(contentLength) {
            responseLog += "\nBody: <\(length) bytes of data>"
        } else {
            responseLog += "\nBody: <none or streaming>"
        }
        
        responseLog += "\n==========================================="
        
        request.logger.info("\(responseLog)")
    }
    
    /// Attempts to pretty-format a JSON string
    private func prettyFormatJSON(_ jsonString: String) -> String {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return jsonString
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                return prettyString
            }
        } catch {
            // If JSON parsing fails, return the original string
        }
        
        return jsonString
    }
} 