import Foundation

struct GrokCodePromptAssembler {
    var runtimeUserInfo: [String: String] = [:]

    func assemble(
        task: String?,
        state: GrokCodeSessionState,
        transcript: [GrokCodeMessageEnvelope] = []
    ) -> String {
        var sections: [String] = []

        sections.append("""
        You are Grok Code, a local coding agent running inside the grok CLI.
        Use local Responses API function calls when tools are available. Do not claim to have changed files unless a local tool result confirms the change.
        """)

        sections.append("""
        Operating Rules:
        - Follow all user, tool, system, and project instructions precisely and completely.
        - This is a real local environment with shell and filesystem access, not a simulation.
        - Use tools to investigate, edit, and verify work yourself instead of telling the user what to run.
        - If a command or edit fails, diagnose the failure and try an appropriate alternative.
        - Use read_file before search_replace edits so stale-file protection can keep edits safe.
        - For new files or generated projects, prefer apply_patch. Use run_terminal_cmd for validation and commands that are simpler in a shell.
        """)

        sections.append("""
        Runtime:
        - cwd: \(state.cwd.path)
        - model: \(state.model.id)
        - permission mode: \(state.options.permissionMode.codeRawValue)
        - max turns: \(state.options.maxTurns)
        - active tools: \(state.options.activeToolNames.joined(separator: ", "))
        """)

        if !state.options.rules.isEmpty {
            sections.append("""
            User Rules:
            \(state.options.rules.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        if let projectInstructions = projectInstructions(startingAt: state.cwd) {
            sections.append("Project Instructions:\n\(projectInstructions)")
        }

        if !runtimeUserInfo.isEmpty {
            let info = runtimeUserInfo
                .sorted { $0.key < $1.key }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            sections.append("Runtime User Info:\n\(info)")
        }

        let projected = GrokCodeContextProjector.project(transcript)
        if !projected.isEmpty {
            let transcriptText = projected.map { message in
                "[\(message.role.rawValue) \(message.kind.rawValue)] \(message.content)"
            }.joined(separator: "\n\n")
            sections.append("Transcript Context:\n\(transcriptText)")
        }

        if let task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("User Task:\n\(task)")
        } else {
            sections.append("User Task:\nStart an interactive coding session and ask for the next task.")
        }

        return sections.joined(separator: "\n\n")
    }

    private func projectInstructions(startingAt cwd: URL) -> String? {
        var path = cwd.standardizedFileURL.path
        var seen: Set<String> = []

        while !seen.contains(path) {
            seen.insert(path)
            let candidate = URL(fileURLWithPath: path).appendingPathComponent("AGENTS.md")
            if let text = try? String(contentsOf: candidate, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.count > 40_000
                    ? String(text.prefix(40_000)) + "\n[AGENTS.md truncated]"
                    : text
            }

            if path == "/" {
                break
            }
            let parent = NSString(string: path).deletingLastPathComponent
            if parent.isEmpty || parent == path {
                break
            }
            path = parent
        }

        return nil
    }
}
