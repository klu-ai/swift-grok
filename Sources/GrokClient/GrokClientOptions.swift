import Foundation

public struct GrokMessageOptions {
    public var enableReasoning: Bool
    public var enableDeepSearch: Bool
    public var disableSearch: Bool
    public var customInstructions: String
    public var temporary: Bool
    public var personalityType: GrokClient.PersonalityType
    public var modeId: String
    public var fileAttachments: [String]
    public var workspaceIds: [String]
    public var disabledConnectorIds: [String]

    public init(
        enableReasoning: Bool = true,
        enableDeepSearch: Bool = false,
        disableSearch: Bool = false,
        customInstructions: String = "",
        temporary: Bool = false,
        personalityType: GrokClient.PersonalityType = .none,
        modeId: String = GrokClient.defaultModeId,
        fileAttachments: [String] = [],
        workspaceIds: [String] = [],
        disabledConnectorIds: [String] = []
    ) {
        self.enableReasoning = enableReasoning
        self.enableDeepSearch = enableDeepSearch
        self.disableSearch = disableSearch
        self.customInstructions = customInstructions
        self.temporary = temporary
        self.personalityType = personalityType
        self.modeId = modeId
        self.fileAttachments = fileAttachments
        self.workspaceIds = workspaceIds
        self.disabledConnectorIds = disabledConnectorIds
    }
}

public struct GrokTaskCreateOptions {
    public var name: String
    public var metadataJsonString: String
    public var schedule: GrokTaskSchedule?
    public var notificationMethod: String
    public var modelMode: String
    public var notificationDeciderEnable: Bool
    public var notificationDeciderGuideline: String
    public var modelName: String
    public var toolset: [String]

    public init(
        name: String = "",
        metadataJsonString: String = "{}",
        schedule: GrokTaskSchedule? = nil,
        notificationMethod: String = "DEFAULT",
        modelMode: String = "BASE",
        notificationDeciderEnable: Bool = true,
        notificationDeciderGuideline: String = "only notify if it's economically valuable",
        modelName: String = "",
        toolset: [String] = [""]
    ) {
        self.name = name
        self.metadataJsonString = metadataJsonString
        self.schedule = schedule
        self.notificationMethod = notificationMethod
        self.modelMode = modelMode
        self.notificationDeciderEnable = notificationDeciderEnable
        self.notificationDeciderGuideline = notificationDeciderGuideline
        self.modelName = modelName
        self.toolset = toolset
    }
}

public struct GrokWorkspaceCreateOptions {
    public var name: String
    public var icon: String
    public var customPersonality: String
    public var preferredModel: String

    public init(
        name: String = "workspace",
        icon: String = "l:book-open:lime",
        customPersonality: String = "New PROJECT WORKSPACE",
        preferredModel: String = "auto"
    ) {
        self.name = name
        self.icon = icon
        self.customPersonality = customPersonality
        self.preferredModel = preferredModel
    }
}

public struct GrokWorkspaceListOptions {
    public var pageSize: Int
    public var orderBy: String

    public init(
        pageSize: Int = 50,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) {
        self.pageSize = pageSize
        self.orderBy = orderBy
    }
}

public struct GrokAssetListOptions {
    public var pageSize: Int
    public var orderBy: String

    public init(
        pageSize: Int = 9,
        orderBy: String = "ORDER_BY_LAST_USE_TIME"
    ) {
        self.pageSize = pageSize
        self.orderBy = orderBy
    }
}

public struct GrokSpeechToTextOptions {
    public var audioFormat: String?
    public var refinementLevel: String

    public init(
        audioFormat: String? = nil,
        refinementLevel: String = GrokClient.defaultSpeechRefinementLevel
    ) {
        self.audioFormat = audioFormat
        self.refinementLevel = refinementLevel
    }
}

public struct GrokShareLinkOptions {
    public var pageSize: Int
    public var allowIndexing: Bool

    public init(
        pageSize: Int = 100,
        allowIndexing: Bool = true
    ) {
        self.pageSize = pageSize
        self.allowIndexing = allowIndexing
    }
}
