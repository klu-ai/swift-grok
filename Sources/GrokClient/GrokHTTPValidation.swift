import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - HTTP Response Validation
extension GrokClient {
    func validateHTTPResponse(_ response: URLResponse, data: Data? = nil, modeId: String? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrokError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GrokError.unauthorized
            case 403:
                let bodyMessage = httpErrorBodyMessage(from: data)
                if responseBodyIndicatesAuthenticationFailure(bodyMessage) {
                    throw GrokError.unauthorized
                }
                throw GrokError.accessDenied(accessDeniedMessage(bodyMessage: bodyMessage, modeId: modeId))
            case 404:
                throw GrokError.notFound
            default:
                let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = body?.isEmpty == false ? ": \(body!.prefix(600))" : ""
                throw GrokError.apiError("HTTP Error: \(httpResponse.statusCode)\(suffix)")
            }
        }
    }

    func httpErrorBodyMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            if let dict = json as? [String: Any] {
                if let error = dict["error"] {
                    return trimmedMessage(describeAPIError(error))
                }
                if let message = stringValue(dict, keys: ["message", "description", "detail"]) {
                    return trimmedMessage(message)
                }
            }

            return trimmedMessage(String(describing: json))
        }

        return trimmedMessage(String(data: data, encoding: .utf8))
    }

    func responseBodyIndicatesAuthenticationFailure(_ message: String?) -> Bool {
        guard let message else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("unauthorized") ||
            normalized.contains("unauthenticated") ||
            normalized.contains("not authenticated") ||
            normalized.contains("authentication required") ||
            normalized.contains("login required") ||
            normalized.contains("log in") ||
            (normalized.contains("cookie") && (normalized.contains("invalid") || normalized.contains("expired"))) ||
            normalized.contains("csrf") ||
            normalized.contains("sso")
    }

    func accessDeniedMessage(bodyMessage: String?, modeId: String?) -> String {
        let resolvedMode = modeId.map(GrokMode.resolve)
        let subject: String
        if let resolvedMode {
            subject = "\(resolvedMode.displayName) (\(resolvedMode.id))"
        } else {
            subject = "this request"
        }

        var message = "Grok denied access to \(subject)."
        if let bodyMessage, !isGenericForbiddenMessage(bodyMessage) {
            message += " \(bodyMessage)"
        } else {
            message += " The selected model or feature may not be available to your account."
        }
        message += " Switch models with `/model` or pass `--model fast`, `--model expert`, or `--model auto`."
        return message
    }

    func describeAPIError(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any] {
            if let message = stringValue(dict, keys: ["message", "error", "description"]) {
                return message
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return String(describing: value)
    }

    private func trimmedMessage(_ message: String?) -> String? {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(600))
    }

    private func isGenericForbiddenMessage(_ message: String) -> Bool {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "forbidden" ||
            normalized == "access denied" ||
            normalized == "{\"error\":\"forbidden\"}" ||
            normalized == "{\"error\":\"access denied\"}"
    }

    private func stringValue(_ dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else {
            return nil
        }

        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
