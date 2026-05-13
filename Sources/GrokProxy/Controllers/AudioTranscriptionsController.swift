import Foundation
import NIOCore
import Vapor

typealias AudioTranscriptionHandler = @Sendable (AudioTranscriptionRequest) async throws -> String

struct AudioTranscriptionsController: RouteCollection {
    private let transcribe: AudioTranscriptionHandler

    init(transcribe: @escaping AudioTranscriptionHandler) {
        self.transcribe = transcribe
    }

    func boot(routes: RoutesBuilder) throws {
        routes.grouped("v1").post("audio", "transcriptions") { [transcribe] req in
            try await self.transcriptions(req: req, transcribe: transcribe)
        }
    }

    @Sendable
    private func transcriptions(
        req: Request,
        transcribe: AudioTranscriptionHandler
    ) async throws -> Response {
        let transcriptionRequest = try decodeRequest(req)

        switch transcriptionRequest.responseFormat {
        case "json":
            let text = try await transcribe(transcriptionRequest)
            let response = AudioTranscriptionResponse(text: text)
            return try await response.encodeResponse(status: .ok, for: req)
        case "text":
            let text = try await transcribe(transcriptionRequest)
            var headers = HTTPHeaders()
            headers.contentType = .plainText
            return Response(status: .ok, headers: headers, body: .init(string: text))
        default:
            throw Abort(.badRequest, reason: "Unsupported response_format: \(transcriptionRequest.responseFormat)")
        }
    }

    private func decodeRequest(_ req: Request) throws -> AudioTranscriptionRequest {
        if let contentType = req.headers.contentType,
           contentType.type == "application",
           contentType.subType == "json" {
            let body = try req.content.decode(AudioTranscriptionJSONRequest.self)
            guard let audioBase64 = body.audioBase64 ?? body.audio_base64 ?? body.content ?? body.data ?? body.file,
                  !audioBase64.isEmpty else {
                throw Abort(.badRequest, reason: "JSON transcription requests require file, audioBase64, content, or data")
            }
            let trimmedAudioBase64 = audioBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Data(base64Encoded: trimmedAudioBase64) != nil else {
                throw Abort(.badRequest, reason: "JSON transcription audio must be raw base64")
            }

            return AudioTranscriptionRequest(
                model: body.model,
                audioBase64: trimmedAudioBase64,
                responseFormat: normalizeResponseFormat(body.response_format),
                audioFormat: body.audioFormat ?? body.audio_format,
                refinementLevel: body.refinementLevel ?? body.refinement_level,
                language: body.language,
                prompt: body.prompt
            )
        }

        let body = try req.content.decode(AudioTranscriptionMultipartRequest.self)
        var fileData = body.file.data
        let audioBytes = fileData.readData(length: fileData.readableBytes) ?? Data()

        guard !audioBytes.isEmpty else {
            throw Abort(.badRequest, reason: "Multipart transcription requests require a non-empty file")
        }

        return AudioTranscriptionRequest(
            model: body.model,
            audioBase64: audioBytes.base64EncodedString(),
            responseFormat: normalizeResponseFormat(body.response_format),
            audioFormat: body.audio_format ?? inferAudioFormat(from: body.file),
            refinementLevel: body.refinement_level,
            language: body.language,
            prompt: body.prompt
        )
    }

    private func normalizeResponseFormat(_ responseFormat: String?) -> String {
        responseFormat?.lowercased() ?? "json"
    }

    private func inferAudioFormat(from file: File) -> String? {
        if let extensionName = file.filename.split(separator: ".").last {
            return String(extensionName).lowercased()
        }

        guard let contentType = file.contentType else {
            return nil
        }

        return contentType.subType.lowercased()
    }
}
