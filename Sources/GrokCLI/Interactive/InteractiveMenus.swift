import Foundation
import GrokClient
import Rainbow

extension GrokCLI {
    private enum WorkspacePickerSelection {
        case none
        case workspace(GrokWorkspace)
    }

    static func showWorkspacePicker(app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let workspaces = try await client.listWorkspaces(pageSize: 50)
        guard !workspaces.isEmpty else {
            print("No workspaces found.".yellow)
            return
        }

        if stdinIsTTY(), stdoutIsTTY() {
            var items: [PickerItem<WorkspacePickerSelection>] = [
                PickerItem(
                    id: "none",
                    title: "No project",
                    subtitle: "clear project",
                    preview: "New chats will not be project-scoped.",
                    value: .none,
                    searchText: "none no project clear"
                )
            ]
            items += workspaces.map { workspace in
                PickerItem(
                    id: workspace.cliResolvedId ?? workspace.cliDisplayName,
                    title: workspace.cliDisplayName,
                    subtitle: workspace.cliResolvedId,
                    preview: workspace.customPersonality ?? workspace.preferredModel,
                    value: .workspace(workspace)
                )
            }

            guard let selection = InteractivePicker.select(
                title: "Select project",
                items: items,
                currentId: app.getCurrentWorkspace()?.cliResolvedId
            ) else {
                return
            }

            switch selection {
            case .none:
                app.setCurrentWorkspace(nil)
                app.resetConversation()
                print("Workspace cleared. New chats will not be project-scoped.".yellow)
            case .workspace(let workspace):
                app.setCurrentWorkspace(workspace)
                app.resetConversation()
                print("Workspace set to: \(workspace.cliDisplayName)".green)
            }
            return
        }

        if let current = app.getCurrentWorkspace() {
            print("Current workspace: \(current.cliDisplayName)".cyan)
        }

        print("Select workspace:".cyan.bold)
        print("0. None")
        for (index, workspace) in workspaces.enumerated() {
            print("\(index + 1). \(workspace.cliDisplayName) \(workspace.cliResolvedId ?? "")".yellow)
        }
        print("> ".green, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = Int(input),
              selection >= 0,
              selection <= workspaces.count else {
            print("Invalid selection.".red)
            return
        }

        if selection == 0 {
            app.setCurrentWorkspace(nil)
            app.resetConversation()
            print("Workspace cleared. New chats will not be project-scoped.".yellow)
            return
        }

        let workspace = workspaces[selection - 1]
        app.setCurrentWorkspace(workspace)
        app.resetConversation()
        print("Workspace set to: \(workspace.cliDisplayName)".green)
    }

    static func showAttachmentPicker(app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let assets = try await client.listAssets(pageSize: 25)
        guard !assets.isEmpty else {
            print("No files found.".yellow)
            return
        }

        if stdinIsTTY(), stdoutIsTTY() {
            let items = assets.map { asset in
                PickerItem(
                    id: asset.resolvedId ?? asset.cliDisplayName,
                    title: asset.cliDisplayName,
                    subtitle: asset.resolvedId,
                    preview: asset.mimeType,
                    value: asset
                )
            }
            guard let asset = InteractivePicker.select(title: "Select file", items: items) else {
                return
            }
            guard let fileId = asset.resolvedId else {
                print("Selected file has no usable attachment ID.".red)
                return
            }

            app.addAttachedFileId(fileId)
            print("Attached: \(asset.cliDisplayName)".green)
            return
        }

        print("Select file to attach:".cyan.bold)
        for (index, asset) in assets.enumerated() {
            print("\(index + 1). \(asset.cliDisplayName) \(asset.resolvedId ?? "")".yellow)
        }
        print("> ".green, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = Int(input),
              selection >= 1,
              selection <= assets.count else {
            print("Invalid selection.".red)
            return
        }

        let asset = assets[selection - 1]
        guard let fileId = asset.resolvedId else {
            print("Selected file has no usable attachment ID.".red)
            return
        }

        app.addAttachedFileId(fileId)
        print("Attached: \(asset.cliDisplayName)".green)
    }

    static func uploadAndAttachFile(path: String, app: GrokCLIApp) async throws {
        let client = try app.initializeClient()
        let response = try await client.uploadFile(at: path)
        guard let fileId = response.uploadedFileId else {
            throw GrokError.apiError("Uploaded file response did not include an attachment ID")
        }

        app.addAttachedFileId(fileId)
        print("Uploaded and attached: \(response.fileName ?? URL(fileURLWithPath: path).lastPathComponent)".green)
        print("File ID: \(fileId)".cyan)
    }

    static func attachUploadPath(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "/attach upload"
        let lowercased = trimmed.lowercased()
        guard lowercased == prefix || lowercased.hasPrefix(prefix + " ") else {
            return nil
        }

        let pathStart = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let rawPath = trimmed[pathStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return stripMatchingQuotes(rawPath)
    }

    static func stripMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return value
        }
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

}
