import Foundation
import GrokClient

struct ChatSessionState {
    var reasoning: Bool
    var deepSearch: Bool
    var noSearch: Bool
    var privateMode: Bool
    var stream: Bool
    var mode: GrokMode
    var outputFormat: OutputFormat
    var rateLimitStatus: String? = nil

    func workspaceIds(app: GrokCLIApp) -> [String] {
        app.getCurrentWorkspaceIds()
    }
}
