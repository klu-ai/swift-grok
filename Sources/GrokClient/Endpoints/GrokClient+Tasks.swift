import Foundation

extension GrokClient {
    public func listTasksResponse() async throws -> GrokTasksResponse {
        let path = try endpointPath(["tasks"], queryItems: [])
        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTaskParserTasksResponse(from: json)
    }

    public func listTasks() async throws -> [GrokTask] {
        try await listTasksResponse().tasks
    }

    public func listInactiveTasksResponse() async throws -> GrokTasksResponse {
        let path = try endpointPath(["tasks", "inactive"], queryItems: [])
        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTaskParserTasksResponse(from: json, defaultIsEnabled: false)
    }

    public func listInactiveTasks() async throws -> [GrokTask] {
        try await listInactiveTasksResponse().tasks
    }

    public func taskResultsResponse(taskId: String, limit: Int = 1) async throws -> GrokTaskResultsResponse {
        let path = try endpointPath(
            ["tasks", "results", taskId],
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )

        let request = try makeRequest(path: path, method: "GET", namespace: .root)
        let json = try await jsonObject(for: request)
        return makeTaskParserTaskResultsResponse(from: json)
    }

    public func taskResults(taskId: String, limit: Int = 1) async throws -> [GrokTaskResult] {
        try await taskResultsResponse(taskId: taskId, limit: limit).results
    }

    public func latestTaskResult(taskId: String) async throws -> GrokTaskResult? {
        try await taskResults(taskId: taskId, limit: 1).first
    }

    public func createTask(
        prompt: String,
        options: GrokTaskCreateOptions
    ) async throws -> GrokTaskMutationResponse {
        guard let schedule = options.schedule else {
            throw GrokError.apiError("Task create options must include a schedule")
        }

        let payload = taskEndpointCreatePayload(
            prompt: prompt,
            options: options,
            schedule: schedule
        )

        let path = try endpointPath(["tasks"], queryItems: [])
        let request = try makeRequest(path: path, payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let task = firstTaskMutationDictionary(from: json)
            .map { makeTaskParserTask(from: $0) }

        return GrokTaskMutationResponse(task: task, rawJSON: AnyCodable(json))
    }

    public func createTask(
        name: String = "",
        prompt: String,
        metadataJsonString: String = "{}",
        schedule: GrokTaskSchedule,
        notificationMethod: String = "DEFAULT",
        modelMode: String = "BASE",
        notificationDeciderEnable: Bool = true,
        notificationDeciderGuideline: String = "only notify if it's economically valuable",
        modelName: String = "",
        toolset: [String] = [""]
    ) async throws -> GrokTaskMutationResponse {
        let options = GrokTaskCreateOptions(
            name: name,
            metadataJsonString: metadataJsonString,
            schedule: schedule,
            notificationMethod: notificationMethod,
            modelMode: modelMode,
            notificationDeciderEnable: notificationDeciderEnable,
            notificationDeciderGuideline: notificationDeciderGuideline,
            modelName: modelName,
            toolset: toolset
        )

        return try await createTask(prompt: prompt, options: options)
    }

    public func createTask(
        prompt: String,
        date: String,
        time: String,
        timezone: String,
        options: GrokTaskCreateOptions
    ) async throws -> GrokTask {
        let schedule = GrokTaskSchedule(
            taskCadence: "TASK_CADENCE_ONCE",
            isEnabled: true,
            timezone: timezone,
            timeOfDay: time,
            dayOfYear: date
        )
        let scheduledOptions = GrokTaskCreateOptions(
            name: options.name,
            metadataJsonString: options.metadataJsonString,
            schedule: schedule,
            notificationMethod: options.notificationMethod,
            modelMode: options.modelMode,
            notificationDeciderEnable: options.notificationDeciderEnable,
            notificationDeciderGuideline: options.notificationDeciderGuideline,
            modelName: options.modelName,
            toolset: options.toolset
        )
        let response = try await createTask(prompt: prompt, options: scheduledOptions)

        if let task = response.task {
            return task
        }

        return GrokTask(rawJSON: ["response": response.rawJSON])
    }

    public func createTask(
        prompt: String,
        name: String? = nil,
        date: String,
        time: String,
        timezone: String,
        guideline: String? = nil,
        notificationMethod: String = "DEFAULT",
        modelMode: String = "BASE",
        notificationDeciderEnable: Bool = true,
        metadataJsonString: String = "{}",
        modelName: String = "",
        toolset: [String] = [""]
    ) async throws -> GrokTask {
        let options = GrokTaskCreateOptions(
            name: name ?? "",
            metadataJsonString: metadataJsonString,
            notificationMethod: notificationMethod,
            modelMode: modelMode,
            notificationDeciderEnable: notificationDeciderEnable,
            notificationDeciderGuideline: guideline ?? "only notify if it's economically valuable",
            modelName: modelName,
            toolset: toolset
        )

        return try await createTask(
            prompt: prompt,
            date: date,
            time: time,
            timezone: timezone,
            options: options
        )
    }

    public func archiveTask(taskId: String, isEnabled: Bool) async throws -> GrokTaskMutationResponse {
        let payload: [String: Any] = [
            "taskId": taskId,
            "isEnabled": isEnabled
        ]

        let path = try endpointPath(["tasks", "archive"], queryItems: [])
        let request = try makeRequest(path: path, method: "PUT", payload: payload, namespace: .root)
        let json = try await jsonObject(for: request)
        let task = firstTaskMutationDictionary(from: json)
            .map { makeTaskParserTask(from: $0) }

        return GrokTaskMutationResponse(task: task, rawJSON: AnyCodable(json))
    }

    private func firstTaskMutationDictionary(from json: Any) -> [String: AnyCodable]? {
        JSONLookup(json).firstDictionary(["task", "data", "result"]) ??
            JSONLookup(json).rawAnyCodable.value as? [String: AnyCodable]
    }
}

private func taskEndpointCreatePayload(
    prompt: String,
    options: GrokTaskCreateOptions,
    schedule: GrokTaskSchedule
) -> [String: Any] {
    [
        "name": options.name,
        "prompt": prompt,
        "metadataJsonString": options.metadataJsonString,
        "schedule": [
            "taskCadence": schedule.taskCadence,
            "isEnabled": schedule.isEnabled,
            "timezone": schedule.timezone,
            "timeOfDay": schedule.timeOfDay,
            "dayOfYear": schedule.dayOfYear
        ],
        "notificationMethod": options.notificationMethod,
        "modelMode": options.modelMode,
        "notificationDeciderEnable": options.notificationDeciderEnable,
        "notificationDeciderGuideline": options.notificationDeciderGuideline,
        "modelName": options.modelName,
        "toolset": options.toolset
    ]
}
