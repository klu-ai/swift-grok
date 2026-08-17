import Foundation
import GrokClient

extension GrokCLIApp {
    func validXAIOAuthCredential() async throws -> XAIOAuthCredential {
        guard var credential = try configManager.loadOAuthCredential() else {
            throw GrokError.invalidCredentials
        }

        if credential.expiresSoon {
            let oauthClient = try XAIOAuthClient()
            credential = try await oauthClient.refresh(credential)
            _ = try configManager.saveOAuthCredential(credential, select: false)
        }

        return credential
    }

    func authenticateWithXAIOAuth(onDeviceCode: (XAIDeviceAuthorization) -> Void) async throws -> (credential: XAIOAuthCredential, credentialPath: String) {
        let oauthClient = try XAIOAuthClient()
        let credential = try await oauthClient.authenticateWithDeviceCode(onDeviceCode: onDeviceCode)
        let path = try configManager.saveOAuthCredential(credential)
        cachedXAIOAuthModelIDs = nil
        return (credential, path)
    }

    func savedXAIOAuthStatus() throws -> (credential: XAIOAuthCredential?, credentialPath: String?) {
        try (configManager.loadOAuthCredential(), configManager.getSavedOAuthCredentialsPath())
    }

    func verifyXAIOAuthCredential(sendTestResponse: Bool = false) async throws -> XAIOAuthVerificationResult {
        guard var credential = try configManager.loadOAuthCredential(),
              let credentialPath = configManager.getSavedOAuthCredentialsPath() else {
            throw GrokError.invalidCredentials
        }

        let oauthClient = try XAIOAuthClient()
        if credential.expiresSoon {
            credential = try await oauthClient.refresh(credential)
            _ = try configManager.saveOAuthCredential(credential, select: false)
        }

        let models = try await oauthClient.listModels(using: credential)
        cachedXAIOAuthModelIDs = models
        let response: (id: String, text: String?)?
        if sendTestResponse {
            response = try await oauthClient.createTinyResponse(using: credential)
        } else {
            response = nil
        }

        return XAIOAuthVerificationResult(
            credential: credential,
            credentialPath: credentialPath,
            models: models,
            testResponseID: response?.id,
            testResponseText: response?.text
        )
    }

    func loadXAIOAuthModelIDsIfAvailable() async -> [String] {
        if let cachedXAIOAuthModelIDs {
            return cachedXAIOAuthModelIDs
        }

        do {
            guard var credential = try configManager.loadOAuthCredential() else {
                cachedXAIOAuthModelIDs = []
                return []
            }

            let oauthClient = try XAIOAuthClient()
            if credential.expiresSoon {
                credential = try await oauthClient.refresh(credential)
                _ = try configManager.saveOAuthCredential(credential, select: false)
            }

            let modelIDs = try await oauthClient.listModels(using: credential)
            cachedXAIOAuthModelIDs = modelIDs
            return modelIDs
        } catch {
            if getDebugMode() {
                print("Debug: Could not load xAI OAuth API models: \(error.localizedDescription)")
            }
            cachedXAIOAuthModelIDs = []
            return []
        }
    }

    func resolveXAIOAuthModel(_ mode: GrokMode) async -> GrokMode {
        let modelIDs = await loadXAIOAuthModelIDsIfAvailable()
        let requested = mode.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelIDs.contains(requested) {
            return GrokMode(id: requested, displayName: requested, summary: "xAI API model")
        }

        let normalized = requested
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        let preferred: String
        switch normalized {
        case "fast", "non-reasoning", "quick":
            preferred = modelIDs.first(where: { $0.contains("non-reasoning") }) ?? "grok-4.3"
        case "auto", "expert", "reasoning", "think", "heavy":
            preferred = modelIDs.first(where: { $0.contains("reasoning") && !$0.contains("non-reasoning") }) ?? "grok-4.3"
        case "grok-420-computer-use-sa", "grok-4.3", "grok-4-3", "grok-43", "4.3", "43", "beta", "grok-4.3-beta":
            preferred = modelIDs.contains("grok-4.3") ? "grok-4.3" : (modelIDs.first ?? "grok-4.3")
        default:
            preferred = requested.isEmpty ? (modelIDs.first ?? "grok-4.3") : requested
        }

        return GrokMode(id: preferred, displayName: preferred, summary: "xAI API model")
    }

    func defaultXAIOAuthMode() async -> GrokMode {
        let modelIDs = await loadXAIOAuthModelIDsIfAvailable()
        let preferred = modelIDs.contains("grok-4.3") ? "grok-4.3" : (modelIDs.first ?? "grok-4.3")
        return GrokMode(id: preferred, displayName: preferred, summary: "xAI API model")
    }

    func sendXAIOAuthMessage(
        message: String,
        mode: GrokMode,
        temporary: Bool,
        fileAttachments: [String],
        videoReferenceImages: [XAIVideoReferenceImage] = []
    ) async throws -> ConversationResponse {
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        let resolvedMode = await resolveXAIOAuthModel(mode)

        if resolvedMode.isXAIOAuthImageGenerationModel {
            try validateXAIOAuthMediaAttachments(fileAttachments)
            let response = try await oauthClient.generateImage(
                using: credential,
                modelID: resolvedMode.id,
                prompt: message
            )
            let conversationId = recordXAIOAuthMediaResponse(mode: resolvedMode)
            return ConversationResponse(
                message: response.text,
                conversationId: conversationId,
                responseId: response.id,
                timestamp: Date(),
                isFinal: true
            )
        }

        if resolvedMode.isXAIOAuthVideoGenerationModel {
            try validateXAIOAuthMediaAttachments(fileAttachments)
            let response = try await oauthClient.generateVideo(
                using: credential,
                modelID: resolvedMode.id,
                prompt: message,
                referenceImages: videoReferenceImages
            )
            let conversationId = recordXAIOAuthMediaResponse(mode: resolvedMode)
            return ConversationResponse(
                message: response.text,
                conversationId: conversationId,
                responseId: response.id,
                timestamp: Date(),
                isFinal: true
            )
        }

        let previousResponseID = temporary ? nil : getLastResponseId()
        let response = try await oauthClient.createResponse(
            using: credential,
            modelID: resolvedMode.id,
            message: message,
            previousResponseID: previousResponseID,
            store: !temporary,
            fileAttachmentIDs: fileAttachments
        )

        let conversationId = recordXAIOAuthResponse(responseId: response.id, mode: resolvedMode)

        return ConversationResponse(
            message: response.text ?? "",
            conversationId: conversationId,
            responseId: response.id,
            timestamp: Date(),
            isFinal: true
        )
    }

    func streamXAIOAuthMessage(
        message: String,
        mode: GrokMode,
        temporary: Bool,
        fileAttachments: [String],
        videoReferenceImages: [XAIVideoReferenceImage] = []
    ) async throws -> (stream: AsyncThrowingStream<ConversationResponse, Error>, mode: GrokMode) {
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        let resolvedMode = await resolveXAIOAuthModel(mode)

        if resolvedMode.isXAIOAuthImageGenerationModel || resolvedMode.isXAIOAuthVideoGenerationModel {
            try validateXAIOAuthMediaAttachments(fileAttachments)
            let stream = AsyncThrowingStream<ConversationResponse, Error> { continuation in
                let task = Task {
                    do {
                        let response: XAIMediaGenerationResponse
                        if resolvedMode.isXAIOAuthImageGenerationModel {
                            response = try await oauthClient.generateImage(
                                using: credential,
                                modelID: resolvedMode.id,
                                prompt: message
                            )
                        } else {
                            response = try await oauthClient.generateVideo(
                                using: credential,
                                modelID: resolvedMode.id,
                                prompt: message,
                                referenceImages: videoReferenceImages,
                                onPoll: { update in
                                    let progressSuffix = update.progress.map { " \($0)%" } ?? ""
                                    continuation.yield(ConversationResponse(
                                        message: "Video generation \(update.status)\(progressSuffix)",
                                        conversationId: "xai-oauth",
                                        responseId: update.requestID,
                                        timestamp: Date(),
                                        isThinking: true
                                    ))
                                }
                            )
                        }

                        continuation.yield(ConversationResponse(
                            message: response.text,
                            conversationId: "xai-oauth",
                            responseId: response.id,
                            timestamp: Date(),
                            isFinal: true
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
            return (stream, resolvedMode)
        }

        let previousResponseID = temporary ? nil : getLastResponseId()
        let stream = try oauthClient.streamResponse(
            using: credential,
            modelID: resolvedMode.id,
            message: message,
            previousResponseID: previousResponseID,
            store: !temporary,
            fileAttachmentIDs: fileAttachments
        )
        return (stream, resolvedMode)
    }

    func transcribeWithXAIOAuth(audioData: Data, fileName: String, mimeType: String) async throws -> GrokSpeechToTextResponse {
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        return try await oauthClient.transcribeAudio(
            using: credential,
            audioData: audioData,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func uploadFileWithXAIOAuth(at path: String, mimeType: String?) async throws -> GrokFileUploadResponse {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)
        let data = try Data(contentsOf: fileURL)
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        return try await oauthClient.uploadFile(
            using: credential,
            fileData: data,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType ?? "application/octet-stream"
        )
    }

    func listFilesWithXAIOAuth(pageSize: Int) async throws -> GrokAssetsResponse {
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        return try await oauthClient.listFiles(using: credential, pageSize: pageSize)
    }

    func deleteFileWithXAIOAuth(fileID: String) async throws -> GrokFileMutationResponse {
        let credential = try await validXAIOAuthCredential()
        let oauthClient = try XAIOAuthClient()
        return try await oauthClient.deleteFile(using: credential, fileID: fileID)
    }

    private func validateXAIOAuthMediaAttachments(_ fileAttachments: [String]) throws {
        let hasAttachments = fileAttachments.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !hasAttachments else {
            throw GrokError.apiError("xAI OAuth media generation currently supports prompt-only requests from the CLI; remove file attachments and try again.")
        }
    }
}

extension GrokMode {
    var isXAIOAuthImageGenerationModel: Bool {
        let normalized = id.lowercased()
        return normalized.contains("imagine-image") ||
            normalized.hasPrefix("grok-2-image") ||
            normalized.contains("image-generation")
    }

    var isXAIOAuthVideoGenerationModel: Bool {
        let normalized = id.lowercased()
        return normalized.contains("imagine-video") || normalized.contains("video-generation")
    }

    var isXAIOAuthMediaGenerationModel: Bool {
        isXAIOAuthImageGenerationModel || isXAIOAuthVideoGenerationModel
    }
}
