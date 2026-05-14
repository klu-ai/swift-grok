import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - URLRequest Extension for curl representation
extension URLRequest {
    func curlRepresentation(redactCookies: Bool = false) -> String {
        var components = ["curl"]
        if let method = self.httpMethod, method != "GET" {
            components.append("-X \(method)")
        }
        if let headers = self.allHTTPHeaderFields {
            for (key, value) in headers {
                let redactedHeaders = ["authorization", "cookie", "proxy-authorization", "set-cookie"]
                let headerValue = redactCookies && redactedHeaders.contains(key.lowercased()) ? "<redacted>" : value
                components.append("-H \"\(key): \(headerValue)\"")
            }
        }
        if let bodyData = self.httpBody, let body = redactedBodyString(from: bodyData) {
            // Escape single quotes in the body
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            components.append("--data '\(escapedBody)'")
        }
        if let url = self.url {
            components.append("\"\(url.absoluteString)\"")
        }
        return components.joined(separator: " ")
    }

    private func redactedBodyString(from bodyData: Data) -> String? {
        guard let body = String(data: bodyData, encoding: .utf8) else {
            return nil
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: bodyData, options: []),
            let redacted = redactedJSONValue(json),
            JSONSerialization.isValidJSONObject(redacted),
            let redactedData = try? JSONSerialization.data(withJSONObject: redacted, options: []),
            let redactedBody = String(data: redactedData, encoding: .utf8)
        else {
            return body
        }

        return redactedBody
    }

    private func redactedJSONValue(_ value: Any) -> Any? {
        let sensitiveKeys = Set(["audiobase64", "content", "data", "file"])

        if let dictionary = value as? [String: Any] {
            var redacted = [String: Any]()
            var changed = false

            for (key, nestedValue) in dictionary {
                if sensitiveKeys.contains(key.lowercased()) {
                    redacted[key] = redactedDescription(for: nestedValue)
                    changed = true
                } else if let nestedRedacted = redactedJSONValue(nestedValue) {
                    redacted[key] = nestedRedacted
                    changed = true
                } else {
                    redacted[key] = nestedValue
                }
            }

            return changed ? redacted : nil
        }

        if let array = value as? [Any] {
            var changed = false
            let redacted = array.map { nestedValue -> Any in
                if let nestedRedacted = redactedJSONValue(nestedValue) {
                    changed = true
                    return nestedRedacted
                }
                return nestedValue
            }

            return changed ? redacted : nil
        }

        return nil
    }

    private func redactedDescription(for value: Any) -> String {
        if let string = value as? String {
            return "<redacted \(string.count) chars>"
        }

        if let data = value as? Data {
            return "<redacted \(data.count) bytes>"
        }

        if let array = value as? [Any] {
            return "<redacted \(array.count) items>"
        }

        if let dictionary = value as? [String: Any] {
            return "<redacted \(dictionary.count) fields>"
        }

        return "<redacted>"
    }
}
