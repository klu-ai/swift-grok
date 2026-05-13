import Foundation
import Vapor

struct AudioTranscriptionRequest: Sendable {
    let model: String
    let audioBase64: String
    let responseFormat: String
    let audioFormat: String?
    let refinementLevel: String?
    let language: String?
    let prompt: String?
}

struct AudioTranscriptionResponse: Content {
    let text: String
}

struct AudioTranscriptionJSONRequest: Content {
    let model: String
    let file: String?
    let audioBase64: String?
    let audio_base64: String?
    let content: String?
    let data: String?
    let response_format: String?
    let audioFormat: String?
    let audio_format: String?
    let refinementLevel: String?
    let refinement_level: String?
    let language: String?
    let prompt: String?
}

struct AudioTranscriptionMultipartRequest: Content {
    let file: File
    let model: String
    let response_format: String?
    let audio_format: String?
    let refinement_level: String?
    let language: String?
    let prompt: String?
}
