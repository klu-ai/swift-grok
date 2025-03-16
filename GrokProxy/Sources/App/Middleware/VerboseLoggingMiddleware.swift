import Vapor
import Foundation

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
        await logRequest(request)
        
        // Get the response from the next middleware in the chain
        let response = try await next.respond(to: request)
        
        // Log the response details
        logResponse(response, for: request)
        
        return response
    }
    
    private func logRequest(_ request: Request) async {
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
        do {
            // Only attempt to read the body if it's JSON content type
            if request.headers.contentType?.isJSON == true, 
               let body = try await request.body.collect().string {
                requestLog += "\nBody:\n\(prettyFormatJSON(body))"
            } else if let contentLength = request.headers.first(name: "content-length"),
                      let length = Int(contentLength) {
                requestLog += "\nBody: <\(length) bytes of non-text data>"
            } else {
                requestLog += "\nBody: <none or streaming>"
            }
        } catch {
            requestLog += "\nBody: <failed to read: \(error.localizedDescription)>"
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
        do {
            if response.headers.contentType?.isJSON == true,
               let bodyString = response.body.string {
                responseLog += "\nBody:\n\(prettyFormatJSON(bodyString))"
            } else if let contentLength = response.headers.first(name: "content-length"),
                      let length = Int(contentLength) {
                responseLog += "\nBody: <\(length) bytes of non-text data>"
            } else {
                responseLog += "\nBody: <none or streaming>"
            }
        } catch {
            responseLog += "\nBody: <failed to read: \(error.localizedDescription)>"
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