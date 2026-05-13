import Foundation
import GrokClient

extension GrokWorkspace {
    var cliResolvedId: String? {
        workspaceId ?? id
    }

    var cliDisplayName: String {
        name ?? title ?? cliResolvedId ?? "Untitled workspace"
    }
}

extension GrokAsset {
    var cliDisplayName: String {
        fileName ?? name ?? resolvedId ?? "Untitled file"
    }
}
