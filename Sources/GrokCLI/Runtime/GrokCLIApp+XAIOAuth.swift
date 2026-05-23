import Foundation
import GrokClient

extension GrokCLIApp {
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
            _ = try configManager.saveOAuthCredential(credential)
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
                _ = try configManager.saveOAuthCredential(credential)
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
}
