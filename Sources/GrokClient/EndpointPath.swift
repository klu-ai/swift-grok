import Foundation

internal func encodedPathSegment(_ segment: String) -> String {
    var allowedCharacters = CharacterSet.urlPathAllowed
    allowedCharacters.remove(charactersIn: "/?&")
    return segment.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? segment
}

internal func endpointPath(_ segments: [String], queryItems: [URLQueryItem]) throws -> String {
    var components = URLComponents()
    components.percentEncodedPath = "/" + segments
        .map(encodedPathSegment(_:))
        .joined(separator: "/")

    if !queryItems.isEmpty {
        components.queryItems = queryItems
    }

    guard let path = components.string else {
        throw GrokError.apiError("Could not build endpoint path")
    }

    return path
}
