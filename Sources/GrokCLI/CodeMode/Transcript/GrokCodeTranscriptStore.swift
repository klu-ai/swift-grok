import Foundation

enum GrokCodeTranscriptStoreError: Error, Equatable {
    case invalidUTF8Line(Int)
}

final class GrokCodeTranscriptStore {
    let url: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func defaultURL(sessionID: UUID) -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("grok-cli", isDirectory: true)
            .appendingPathComponent("code-mode", isDirectory: true)
            .appendingPathComponent("transcripts", isDirectory: true)
        return base.appendingPathComponent("\(sessionID.uuidString).jsonl")
    }

    func append(_ envelope: GrokCodeMessageEnvelope) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(envelope)
        var line = data
        line.append(0x0A)

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    func append(contentsOf envelopes: [GrokCodeMessageEnvelope]) throws {
        for envelope in envelopes {
            try append(envelope)
        }
    }

    func readAll(includeEphemeral: Bool = false) throws -> [GrokCodeMessageEnvelope] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GrokCodeTranscriptStoreError.invalidUTF8Line(0)
        }

        var envelopes: [GrokCodeMessageEnvelope] = []
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let lineData = rawLine.data(using: .utf8) else {
                throw GrokCodeTranscriptStoreError.invalidUTF8Line(offset + 1)
            }

            let envelope = try decoder.decode(GrokCodeMessageEnvelope.self, from: lineData)
            if includeEphemeral || !envelope.isEphemeral {
                envelopes.append(envelope)
            }
        }
        return envelopes
    }
}
