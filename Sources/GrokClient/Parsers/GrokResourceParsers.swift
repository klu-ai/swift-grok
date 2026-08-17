import Foundation

internal enum GrokResourceParsers {
    internal static func makeSkill(from dictionary: [String: Any]) -> GrokSkill {
        makeSkill(from: JSONLookup(dictionary))
    }

    internal static func makeSkill(from dictionary: [String: AnyCodable]) -> GrokSkill {
        makeSkill(from: JSONLookup(dictionary))
    }

    internal static func makeWorkspace(from dictionary: [String: Any]) -> GrokWorkspace {
        makeWorkspace(from: JSONLookup(dictionary))
    }

    internal static func makeWorkspace(from dictionary: [String: AnyCodable]) -> GrokWorkspace {
        makeWorkspace(from: JSONLookup(dictionary))
    }

    internal static func makeAsset(from dictionary: [String: Any]) -> GrokAsset {
        makeAsset(from: JSONLookup(dictionary))
    }

    internal static func makeAsset(from dictionary: [String: AnyCodable]) -> GrokAsset {
        makeAsset(from: JSONLookup(dictionary))
    }

    internal static func makeFileUploadResponse(from json: Any) -> GrokFileUploadResponse {
        let lookup = JSONLookup(json)
        let asset = firstDictionary(in: json, preferredKeys: ["asset", "file", "data", "result"])
            .map { makeAsset(from: $0) }

        return GrokFileUploadResponse(
            fileMetadataId: lookup.firstString("fileMetadataId", "file_metadata_id"),
            fileId: lookup.firstString("fileId", "file_id"),
            assetId: lookup.firstString("assetId", "asset_id"),
            id: lookup.firstString("id"),
            fileName: lookup.firstString("fileName", "file_name", "name"),
            asset: asset,
            rawJSON: AnyCodable(json)
        )
    }

    private static func makeSkill(from lookup: JSONLookup) -> GrokSkill {
        let rawJSON = rawDictionary(from: lookup)
        return GrokSkill(
            skillId: lookup.string("skillId", "skill_id"),
            id: lookup.string("id"),
            name: lookup.string("name"),
            title: lookup.string("title"),
            rawJSON: rawJSON
        )
    }

    private static func makeWorkspace(from lookup: JSONLookup) -> GrokWorkspace {
        let rawJSON = rawDictionary(from: lookup)
        return GrokWorkspace(
            workspaceId: lookup.string("workspaceId", "workspace_id"),
            id: lookup.string("id"),
            name: lookup.string("name"),
            title: lookup.string("title"),
            icon: lookup.string("icon"),
            customPersonality: lookup.string("customPersonality", "custom_personality"),
            preferredModel: lookup.string("preferredModel", "preferred_model"),
            rawJSON: rawJSON
        )
    }

    private static func makeAsset(from lookup: JSONLookup) -> GrokAsset {
        let rawJSON = rawDictionary(from: lookup)
        return GrokAsset(
            assetId: lookup.string("assetId", "asset_id"),
            fileMetadataId: lookup.string("fileMetadataId", "file_metadata_id"),
            fileId: lookup.string("fileId", "file_id"),
            id: lookup.string("id"),
            fileName: lookup.string("fileName", "file_name"),
            name: lookup.string("name"),
            mimeType: lookup.string("mimeType", "mime_type", "fileMimeType"),
            rawJSON: rawJSON
        )
    }

    private static func rawDictionary(from lookup: JSONLookup) -> [String: AnyCodable] {
        (lookup.rawAnyCodable.value as? [String: AnyCodable]) ?? [:]
    }

    private static func firstDictionary(in value: Any, preferredKeys: [String]) -> [String: AnyCodable]? {
        let lookup = JSONLookup(value)
        for key in preferredKeys {
            if let dictionary = lookup.firstDictionary(key) {
                return dictionary
            }
        }

        return lookup.rawAnyCodable.value as? [String: AnyCodable]
    }
}

internal extension GrokClient {
    func makeResourceSkill(from dictionary: [String: Any]) -> GrokSkill {
        GrokResourceParsers.makeSkill(from: dictionary)
    }

    func makeResourceSkill(from dictionary: [String: AnyCodable]) -> GrokSkill {
        GrokResourceParsers.makeSkill(from: dictionary)
    }

    func makeResourceWorkspace(from dictionary: [String: Any]) -> GrokWorkspace {
        GrokResourceParsers.makeWorkspace(from: dictionary)
    }

    func makeResourceWorkspace(from dictionary: [String: AnyCodable]) -> GrokWorkspace {
        GrokResourceParsers.makeWorkspace(from: dictionary)
    }

    func makeResourceAsset(from dictionary: [String: Any]) -> GrokAsset {
        GrokResourceParsers.makeAsset(from: dictionary)
    }

    func makeResourceAsset(from dictionary: [String: AnyCodable]) -> GrokAsset {
        GrokResourceParsers.makeAsset(from: dictionary)
    }

    func makeResourceFileUploadResponse(from json: Any) -> GrokFileUploadResponse {
        GrokResourceParsers.makeFileUploadResponse(from: json)
    }
}
