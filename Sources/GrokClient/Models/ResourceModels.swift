import Foundation

public struct GrokWorkspace: Codable {
    public let workspaceId: String?
    public let id: String?
    public let name: String?
    public let title: String?
    public let icon: String?
    public let customPersonality: String?
    public let preferredModel: String?
    public let rawJSON: [String: AnyCodable]

    public init(
        workspaceId: String? = nil,
        id: String? = nil,
        name: String? = nil,
        title: String? = nil,
        icon: String? = nil,
        customPersonality: String? = nil,
        preferredModel: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.workspaceId = workspaceId
        self.id = id
        self.name = name
        self.title = title
        self.icon = icon
        self.customPersonality = customPersonality
        self.preferredModel = preferredModel
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.workspaceId = rawJSON["workspaceId"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.title = rawJSON["title"]?.value as? String
        self.icon = rawJSON["icon"]?.value as? String
        self.customPersonality = rawJSON["customPersonality"]?.value as? String
        self.preferredModel = rawJSON["preferredModel"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokWorkspacesResponse: Codable {
    public let workspaces: [GrokWorkspace]
    public let rawJSON: AnyCodable
}

public struct GrokWorkspaceMutationResponse: Codable {
    public let workspace: GrokWorkspace?
    public let rawJSON: AnyCodable
}

public struct GrokAsset: Codable {
    public let assetId: String?
    public let fileMetadataId: String?
    public let fileId: String?
    public let id: String?
    public let fileName: String?
    public let name: String?
    public let mimeType: String?
    public let rawJSON: [String: AnyCodable]

    public var resolvedId: String? {
        fileMetadataId ?? fileId ?? assetId ?? id
    }

    public init(
        assetId: String? = nil,
        fileMetadataId: String? = nil,
        fileId: String? = nil,
        id: String? = nil,
        fileName: String? = nil,
        name: String? = nil,
        mimeType: String? = nil,
        rawJSON: [String: AnyCodable] = [:]
    ) {
        self.assetId = assetId
        self.fileMetadataId = fileMetadataId
        self.fileId = fileId
        self.id = id
        self.fileName = fileName
        self.name = name
        self.mimeType = mimeType
        self.rawJSON = rawJSON
    }

    public init(from decoder: Decoder) throws {
        let rawJSON = try [String: AnyCodable](from: decoder)
        self.rawJSON = rawJSON
        self.assetId = rawJSON["assetId"]?.value as? String ?? rawJSON["asset_id"]?.value as? String
        self.fileMetadataId = rawJSON["fileMetadataId"]?.value as? String ?? rawJSON["file_metadata_id"]?.value as? String
        self.fileId = rawJSON["fileId"]?.value as? String ?? rawJSON["file_id"]?.value as? String
        self.id = rawJSON["id"]?.value as? String
        self.fileName = rawJSON["fileName"]?.value as? String ?? rawJSON["file_name"]?.value as? String
        self.name = rawJSON["name"]?.value as? String
        self.mimeType = rawJSON["mimeType"]?.value as? String
            ?? rawJSON["mime_type"]?.value as? String
            ?? rawJSON["fileMimeType"]?.value as? String
    }

    public func encode(to encoder: Encoder) throws {
        try rawJSON.encode(to: encoder)
    }
}

public struct GrokFileUploadResponse: Codable {
    public let fileMetadataId: String?
    public let fileId: String?
    public let assetId: String?
    public let id: String?
    public let fileName: String?
    public let asset: GrokAsset?
    public let rawJSON: AnyCodable

    public var uploadedFileId: String? {
        fileMetadataId ?? fileId ?? assetId ?? id ?? asset?.resolvedId
    }

    public init(
        fileMetadataId: String? = nil,
        fileId: String? = nil,
        assetId: String? = nil,
        id: String? = nil,
        fileName: String? = nil,
        asset: GrokAsset? = nil,
        rawJSON: AnyCodable
    ) {
        self.fileMetadataId = fileMetadataId
        self.fileId = fileId
        self.assetId = assetId
        self.id = id
        self.fileName = fileName
        self.asset = asset
        self.rawJSON = rawJSON
    }
}

public struct GrokAssetsResponse: Codable {
    public let assets: [GrokAsset]
    public let rawJSON: AnyCodable

    public init(assets: [GrokAsset], rawJSON: AnyCodable) {
        self.assets = assets
        self.rawJSON = rawJSON
    }
}

public struct GrokFileMutationResponse: Codable {
    public let asset: GrokAsset?
    public let rawJSON: AnyCodable

    public init(asset: GrokAsset? = nil, rawJSON: AnyCodable) {
        self.asset = asset
        self.rawJSON = rawJSON
    }
}
