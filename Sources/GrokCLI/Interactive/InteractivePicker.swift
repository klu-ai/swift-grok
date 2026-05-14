import Foundation
import Rainbow

#if os(Linux)
import Glibc
private let pickerStdinFileDescriptor = STDIN_FILENO
#else
import Darwin
private let pickerStdinFileDescriptor = STDIN_FILENO
#endif

struct PickerItem<Value> {
    let id: String
    let title: String
    let subtitle: String?
    let metadataLabel: String?
    let metadata: String?
    let previewLabel: String
    let preview: String?
    let value: Value
    let isEnabled: Bool
    let searchText: String

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        metadataLabel: String? = nil,
        metadata: String? = nil,
        previewLabel: String = "preview",
        preview: String? = nil,
        value: Value,
        isEnabled: Bool = true,
        searchText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.metadataLabel = metadataLabel
        self.metadata = metadata
        self.previewLabel = previewLabel
        self.preview = preview
        self.value = value
        self.isEnabled = isEnabled
        self.searchText = searchText ?? [title, subtitle, metadata, preview, id]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

private final class PickerPreviewPrefetcher<Value>: @unchecked Sendable {
    private struct PendingPreview {
        let id: String
        let value: Value
    }

    private let previewProvider: ((Value) async -> String?)?
    private let maxConcurrentRequests = 3
    private let lock = NSLock()
    private var cache: [String: String?] = [:]
    private var inFlight: Set<String> = []
    private var pending: [PendingPreview] = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var updateVersion = 0

    init(previewProvider: ((Value) async -> String?)?) {
        self.previewProvider = previewProvider
    }

    func version() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return updateVersion
    }

    func consumeUpdate(after version: inout Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard updateVersion != version else {
            return false
        }
        version = updateVersion
        return true
    }

    func preview(for item: PickerItem<Value>) -> String? {
        if let preview = item.preview, !preview.isEmpty {
            return preview
        }

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[item.id] {
            return cached
        }
        return nil
    }

    func prioritize(_ items: [PickerItem<Value>]) {
        guard previewProvider != nil else {
            return
        }

        lock.lock()
        defer {
            startAvailableRequestsLocked()
            lock.unlock()
        }

        let wantedIds = Set(items.map(\.id))
        pending.removeAll { !wantedIds.contains($0.id) }

        var existingPending = Set(pending.map(\.id))
        for item in items {
            guard item.isEnabled else { continue }
            guard item.preview?.isEmpty ?? true else { continue }
            guard !cache.keys.contains(item.id), !inFlight.contains(item.id), !existingPending.contains(item.id) else {
                continue
            }

            pending.append(PendingPreview(id: item.id, value: item.value))
            existingPending.insert(item.id)
        }
    }

    func cancelAll() {
        lock.lock()
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        pending.removeAll()
        inFlight.removeAll()
        lock.unlock()

        for task in activeTasks {
            task.cancel()
        }
    }

    private func startAvailableRequestsLocked() {
        guard let previewProvider else {
            return
        }

        while inFlight.count < maxConcurrentRequests, !pending.isEmpty {
            let next = pending.removeFirst()
            inFlight.insert(next.id)
            tasks[next.id] = Task { [weak self] in
                let preview = await previewProvider(next.value)
                guard !Task.isCancelled else {
                    return
                }
                self?.complete(id: next.id, preview: preview)
            }
        }
    }

    private func complete(id: String, preview: String?) {
        lock.lock()
        cache[id] = preview
        inFlight.remove(id)
        tasks.removeValue(forKey: id)
        updateVersion += 1
        startAvailableRequestsLocked()
        lock.unlock()
    }
}

private final class PickerRemoteItemsController<Value>: @unchecked Sendable {
    private let itemsProvider: (String) async throws -> [PickerItem<Value>]
    private let debounceNanoseconds: UInt64
    private let lock = NSLock()

    private var activeQuery = ""
    private var latestItems: [PickerItem<Value>]
    private var latestVersion = 0
    private var isLoadingValue = false
    private var errorMessageValue: String?
    private var scheduledTask: Task<Void, Never>?

    init(
        initialItems: [PickerItem<Value>],
        debounceNanoseconds: UInt64 = 250_000_000,
        itemsProvider: @escaping (String) async throws -> [PickerItem<Value>]
    ) {
        self.latestItems = initialItems
        self.debounceNanoseconds = debounceNanoseconds
        self.itemsProvider = itemsProvider
    }

    deinit {
        scheduledTask?.cancel()
    }

    func snapshot() -> (items: [PickerItem<Value>], version: Int, isLoading: Bool, errorMessage: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (latestItems, latestVersion, isLoadingValue, errorMessageValue)
    }

    func observe(query: String) {
        lock.lock()
        guard activeQuery != query else {
            lock.unlock()
            return
        }

        activeQuery = query
        isLoadingValue = true
        errorMessageValue = nil
        latestVersion += 1
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
                let items = try await itemsProvider(query)
                guard !Task.isCancelled else { return }
                complete(query: query, items: items, errorMessage: nil)
            } catch is CancellationError {
                return
            } catch {
                complete(query: query, items: nil, errorMessage: error.localizedDescription)
            }
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        scheduledTask?.cancel()
        scheduledTask = nil
        isLoadingValue = false
        lock.unlock()
    }

    private func complete(query: String, items: [PickerItem<Value>]?, errorMessage: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard activeQuery == query else {
            return
        }
        if let items {
            latestItems = items
        }
        isLoadingValue = false
        errorMessageValue = errorMessage
        scheduledTask = nil
        latestVersion += 1
    }
}

enum InteractivePicker {
    private static let visibleItemLimit = 8

    static func select<Value>(
        title: String,
        items: [PickerItem<Value>],
        currentId: String? = nil,
        allowsEmptySelection: Bool = true,
        emptyTitle: String? = nil,
        previewProvider: ((Value) async -> String?)? = nil,
        remoteItemsProvider: ((String) async throws -> [PickerItem<Value>])? = nil
    ) -> Value? {
        guard !items.isEmpty || remoteItemsProvider != nil else { return nil }

        guard GrokCLI.stdinIsTTY(), GrokCLI.stdoutIsTTY() else {
            guard !items.isEmpty else { return nil }
            return selectByNumber(
                title: title,
                items: items,
                allowsEmptySelection: allowsEmptySelection,
                emptyTitle: emptyTitle
            )
        }

        return resolveSelection(
            arrowSelection: selectWithArrows(
                title: title,
                items: items,
                currentId: currentId,
                previewProvider: previewProvider,
                remoteItemsProvider: remoteItemsProvider
            ),
            fallback: {
                guard !items.isEmpty else { return nil }
                return selectByNumber(
                    title: title,
                    items: items,
                    allowsEmptySelection: allowsEmptySelection,
                    emptyTitle: emptyTitle
                )
            }
        )
    }

    static func resolveSelection<Value>(
        arrowSelection: ArrowSelection<Value>,
        fallback: () -> Value?
    ) -> Value? {
        switch arrowSelection {
        case .selected(let value):
            return value
        case .cancelled:
            return nil
        case .unavailable:
            return fallback()
        }
    }

    private static func selectByNumber<Value>(
        title: String,
        items: [PickerItem<Value>],
        allowsEmptySelection: Bool,
        emptyTitle: String?
    ) -> Value? {
        print(title.cyan.bold)
        if let emptyTitle {
            print("0. \(emptyTitle)")
        }
        for (index, item) in items.enumerated() {
            let subtitle = item.subtitle.map { "  \($0)" } ?? ""
            let line = "\(index + 1). \(item.title)\(subtitle)"
            print(item.isEnabled ? line.yellow : line.lightBlack)
        }
        print("> ".green, terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return allowsEmptySelection ? nil : nil
        }

        if let emptyTitle, input == "0" {
            _ = emptyTitle
            return nil
        }

        guard let selection = Int(input), selection >= 1, selection <= items.count else {
            print("Invalid selection.".red)
            return nil
        }

        let item = items[selection - 1]
        guard item.isEnabled else {
            print("Selection is unavailable.".yellow)
            return nil
        }
        return item.value
    }

    private static func selectWithArrows<Value>(
        title: String,
        items: [PickerItem<Value>],
        currentId: String?,
        previewProvider: ((Value) async -> String?)?,
        remoteItemsProvider: ((String) async throws -> [PickerItem<Value>])?
    ) -> ArrowSelection<Value> {
        var originalTermios = termios()
        guard tcgetattr(pickerStdinFileDescriptor, &originalTermios) == 0 else {
            return .unavailable
        }

        var rawTermios = originalTermios
        rawTermios.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &rawTermios.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 0
            controlCharacters[Int(VTIME)] = 1
        }

        guard tcsetattr(pickerStdinFileDescriptor, TCSANOW, &rawTermios) == 0 else {
            return .unavailable
        }

        var query = ""
        var renderedLines = 0
        var selectedIndex = initialIndex(items: items, currentId: currentId)
        let previewPrefetcher = PickerPreviewPrefetcher(previewProvider: previewProvider)
        let remoteController = remoteItemsProvider.map {
            PickerRemoteItemsController(initialItems: items, itemsProvider: $0)
        }
        var previewVersion = previewPrefetcher.version()
        var remoteVersion = remoteController?.snapshot().version ?? 0

        defer {
            previewPrefetcher.cancelAll()
            remoteController?.cancel()
            tcsetattr(pickerStdinFileDescriptor, TCSANOW, &originalTermios)
            showCursor()
            fflush(stdout)
        }

        hideCursor()
        var displayedItems = items
        var isLoading = false
        var errorMessage: String?
        var initialRanked = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
        if initialRanked.isEmpty {
            initialRanked = displayedItems
        }
        previewPrefetcher.prioritize(
            previewPrefetchItems(items: initialRanked, selectedIndex: selectedIndex, previousSelectedIndex: nil)
        )
        render(
            title: title,
            query: query,
            items: initialRanked,
            selectedIndex: selectedIndex,
            renderedLines: &renderedLines,
            preview: selectedPreview(items: initialRanked, selectedIndex: selectedIndex, previewPrefetcher: previewPrefetcher),
            isLoading: isLoading,
            errorMessage: errorMessage
        )

        while true {
            guard let byte = readByte() else {
                if let remoteController {
                    let snapshot = remoteController.snapshot()
                    if snapshot.version != remoteVersion {
                        remoteVersion = snapshot.version
                        displayedItems = snapshot.items
                        isLoading = snapshot.isLoading
                        errorMessage = snapshot.errorMessage
                        var ranked = visibleItems(query: query, items: displayedItems, usesRemoteItems: true)
                        if ranked.isEmpty {
                            ranked = displayedItems
                        }
                        selectedIndex = min(selectedIndex, max(ranked.count - 1, 0))
                        previewPrefetcher.prioritize(
                            previewPrefetchItems(items: ranked, selectedIndex: selectedIndex, previousSelectedIndex: nil)
                        )
                        render(
                            title: title,
                            query: query,
                            items: ranked,
                            selectedIndex: selectedIndex,
                            renderedLines: &renderedLines,
                            preview: selectedPreview(items: ranked, selectedIndex: selectedIndex, previewPrefetcher: previewPrefetcher),
                            isLoading: isLoading,
                            errorMessage: errorMessage
                        )
                    }
                }

                if previewPrefetcher.consumeUpdate(after: &previewVersion) {
                    var ranked = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
                    if ranked.isEmpty {
                        ranked = displayedItems
                    }
                    selectedIndex = min(selectedIndex, max(ranked.count - 1, 0))
                    render(
                        title: title,
                        query: query,
                        items: ranked,
                        selectedIndex: selectedIndex,
                        renderedLines: &renderedLines,
                        preview: selectedPreview(items: ranked, selectedIndex: selectedIndex, previewPrefetcher: previewPrefetcher),
                        isLoading: isLoading,
                        errorMessage: errorMessage
                    )
                }
                continue
            }

            var ranked = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
            if ranked.isEmpty {
                ranked = displayedItems
            }
            let previousSelectedIndex = selectedIndex

            switch byte {
            case 3:
                print("^C")
                processExit(130)
            case 4:
                finish(renderedLines: renderedLines)
                return .cancelled
            case 10, 13:
                finish(renderedLines: renderedLines)
                guard ranked.indices.contains(selectedIndex), ranked[selectedIndex].isEnabled else {
                    return .cancelled
                }
                return .selected(ranked[selectedIndex].value)
            case 27:
                switch readEscapeSequence() {
                case .up:
                    selectedIndex = nextIndex(from: selectedIndex, delta: -1, items: ranked)
                case .down:
                    selectedIndex = nextIndex(from: selectedIndex, delta: 1, items: ranked)
                case .pageUp:
                    selectedIndex = nextPageIndex(from: selectedIndex, delta: -visibleItemLimit, items: ranked)
                case .pageDown:
                    selectedIndex = nextPageIndex(from: selectedIndex, delta: visibleItemLimit, items: ranked)
                case .cancelled:
                    finish(renderedLines: renderedLines)
                    return .cancelled
                case .none:
                    break
                }
            case 127, 8:
                if !query.isEmpty {
                    query.removeLast()
                    let nextItems = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
                    selectedIndex = initialIndex(items: nextItems, currentId: currentId)
                    remoteController?.observe(query: query)
                }
            default:
                if byte >= 32, let scalar = UnicodeScalar(Int(byte)) {
                    query.append(Character(scalar))
                    let nextItems = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
                    selectedIndex = initialIndex(items: nextItems, currentId: currentId)
                    remoteController?.observe(query: query)
                }
            }

            if let remoteController {
                let snapshot = remoteController.snapshot()
                displayedItems = snapshot.items
                isLoading = snapshot.isLoading
                errorMessage = snapshot.errorMessage
            }

            ranked = visibleItems(query: query, items: displayedItems, usesRemoteItems: remoteController != nil)
            if ranked.isEmpty {
                ranked = displayedItems
            }
            selectedIndex = min(selectedIndex, max(ranked.count - 1, 0))
            previewPrefetcher.prioritize(
                previewPrefetchItems(
                    items: ranked,
                    selectedIndex: selectedIndex,
                    previousSelectedIndex: previousSelectedIndex
                )
            )
            render(
                title: title,
                query: query,
                items: ranked,
                selectedIndex: selectedIndex,
                renderedLines: &renderedLines,
                preview: selectedPreview(items: ranked, selectedIndex: selectedIndex, previewPrefetcher: previewPrefetcher),
                isLoading: isLoading,
                errorMessage: errorMessage
            )
        }
    }

    enum ArrowSelection<Value> {
        case selected(Value)
        case cancelled
        case unavailable
    }

    private static func rankedItems<Value>(query: String, items: [PickerItem<Value>]) -> [PickerItem<Value>] {
        FuzzyMatcher.ranked(query: query, items: items)
    }

    private static func visibleItems<Value>(
        query: String,
        items: [PickerItem<Value>],
        usesRemoteItems: Bool
    ) -> [PickerItem<Value>] {
        usesRemoteItems ? items : rankedItems(query: query, items: items)
    }

    private static func initialIndex<Value>(items: [PickerItem<Value>], currentId: String?) -> Int {
        if let currentId,
           let currentIndex = items.firstIndex(where: { $0.id == currentId && $0.isEnabled }) {
            return currentIndex
        }
        return items.firstIndex(where: \.isEnabled) ?? 0
    }

    private static func nextIndex<Value>(from currentIndex: Int, delta: Int, items: [PickerItem<Value>]) -> Int {
        guard !items.isEmpty else { return currentIndex }
        var candidate = currentIndex
        for _ in items.indices {
            candidate = (candidate + delta + items.count) % items.count
            if items[candidate].isEnabled {
                return candidate
            }
        }
        return currentIndex
    }

    private static func nextPageIndex<Value>(from currentIndex: Int, delta: Int, items: [PickerItem<Value>]) -> Int {
        guard !items.isEmpty else { return currentIndex }
        let target = min(max(currentIndex + delta, 0), items.count - 1)
        if items[target].isEnabled {
            return target
        }

        let step = delta < 0 ? -1 : 1
        var candidate = target
        while items.indices.contains(candidate) {
            if items[candidate].isEnabled {
                return candidate
            }
            candidate += step
        }
        return currentIndex
    }

    private static func render<Value>(
        title: String,
        query: String,
        items: [PickerItem<Value>],
        selectedIndex: Int,
        renderedLines: inout Int,
        preview: String?,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        clear(renderedLines: renderedLines)

        let windowStart = visibleWindowStart(
            itemCount: items.count,
            selectedIndex: selectedIndex,
            visibleLimit: visibleItemLimit
        )
        let visibleItems = Array(items.dropFirst(windowStart).prefix(visibleItemLimit))
        let width = TerminalLayout.columns()
        let lines = lines(
            title: title,
            query: query,
            items: visibleItems,
            selectedIndex: selectedIndex - windowStart,
            width: width,
            selectedPreviewOverride: preview,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
        for line in lines {
            print(line)
        }
        renderedLines = terminalRowCount(for: lines, width: width)
        if renderedLines > 0 {
            print("\u{001B}[\(renderedLines)A", terminator: "")
        }
        fflush(stdout)
    }

    static func visibleWindowStart(itemCount: Int, selectedIndex: Int, visibleLimit: Int = 8) -> Int {
        guard itemCount > 0, visibleLimit > 0 else { return 0 }
        let clampedSelectedIndex = min(max(selectedIndex, 0), itemCount - 1)
        let maxStart = max(itemCount - visibleLimit, 0)
        if clampedSelectedIndex < visibleLimit {
            return 0
        }
        return min(clampedSelectedIndex - visibleLimit + 1, maxStart)
    }

    static func lines<Value>(
        title: String,
        query: String,
        items: [PickerItem<Value>],
        selectedIndex: Int,
        width: Int = TerminalLayout.columns(),
        selectedPreviewOverride: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) -> [String] {
        let queryLine = isLoading ? "query \(query)  searching..." : "query \(query)"
        var lines = [title.cyan.bold, queryLine.blue]
        let titleWidth = titleColumnWidth(items: items, width: width)

        if items.isEmpty {
            lines.append((errorMessage ?? "No conversations found.").lightBlack)
        } else {
            for (index, item) in items.enumerated() {
                let marker = index == selectedIndex ? "> " : "  "
                let title = paddedEnd(TerminalLayout.truncateEnd(item.title, width: titleWidth), width: titleWidth)
                let subtitle = item.subtitle ?? item.id
                let subtitleWidth = max(0, width - TerminalLayout.visibleLength(marker) - titleWidth - 1)
                let suffix = subtitleWidth > 4 ? " \(TerminalLayout.truncateEnd(subtitle, width: subtitleWidth - 1))" : ""
                let base = "\(marker)\(title)\(suffix)"
                lines.append(item.isEnabled ? (index == selectedIndex ? base.yellow.bold : base.yellow) : base.lightBlack)
            }
        }

        if items.indices.contains(selectedIndex), let metadata = items[selectedIndex].metadata, !metadata.isEmpty {
            lines.append("")
            lines.append((items[selectedIndex].metadataLabel ?? "metadata").cyan)
            lines.append(metadata)
        }

        if items.indices.contains(selectedIndex) {
            let selectedPreview = selectedPreviewOverride ?? items[selectedIndex].preview
            if let selectedPreview, !selectedPreview.isEmpty {
                lines.append("")
                lines.append(items[selectedIndex].previewLabel.cyan)
                lines.append(selectedPreview)
            }
        }

        lines.append("")
        lines.append("enter choose | type filter | esc cancel".blue)
        return lines
    }

    static func previewPrefetchItems<Value>(
        items: [PickerItem<Value>],
        selectedIndex: Int,
        previousSelectedIndex: Int?,
        visibleLimit: Int = visibleItemLimit,
        directionalLookahead: Int = 6,
        oppositeLookahead: Int = 2
    ) -> [PickerItem<Value>] {
        guard !items.isEmpty else { return [] }

        let selectedIndex = min(max(selectedIndex, 0), items.count - 1)
        let direction: Int
        if let previousSelectedIndex, previousSelectedIndex > selectedIndex {
            direction = -1
        } else {
            direction = 1
        }

        var indexes: [Int] = [selectedIndex]

        if directionalLookahead > 0 {
            for offset in 1...directionalLookahead {
                indexes.append(selectedIndex + direction * offset)
            }
        }

        let windowStart = visibleWindowStart(
            itemCount: items.count,
            selectedIndex: selectedIndex,
            visibleLimit: visibleLimit
        )
        indexes.append(contentsOf: windowStart..<min(windowStart + visibleLimit, items.count))

        if oppositeLookahead > 0 {
            for offset in 1...oppositeLookahead {
                indexes.append(selectedIndex - direction * offset)
            }
        }

        var seen = Set<String>()
        var result: [PickerItem<Value>] = []
        for index in indexes where items.indices.contains(index) {
            let item = items[index]
            guard item.isEnabled, seen.insert(item.id).inserted else {
                continue
            }
            result.append(item)
        }
        return result
    }

    private static func selectedPreview<Value>(
        items: [PickerItem<Value>],
        selectedIndex: Int,
        previewPrefetcher: PickerPreviewPrefetcher<Value>
    ) -> String? {
        guard items.indices.contains(selectedIndex) else {
            return nil
        }

        let item = items[selectedIndex]
        return previewPrefetcher.preview(for: item)
    }

    private static func titleColumnWidth<Value>(items: [PickerItem<Value>], width: Int) -> Int {
        let maxTitleWidth = items.map { TerminalLayout.visibleLength($0.title) }.max() ?? 0
        let maxSubtitleWidth = items
            .map { TerminalLayout.visibleLength($0.subtitle ?? $0.id) }
            .max() ?? 0
        let subtitleBudget = min(maxSubtitleWidth, 24)
        let available = max(24, width - 3 - (subtitleBudget > 0 ? subtitleBudget + 1 : 0))
        return max(12, min(maxTitleWidth, available))
    }

    private static func paddedEnd(_ value: String, width: Int) -> String {
        let visibleLength = TerminalLayout.visibleLength(value)
        guard visibleLength < width else { return value }
        return value + String(repeating: " ", count: width - visibleLength)
    }

    static func terminalRowCount(for lines: [String], width: Int) -> Int {
        lines.reduce(0) { total, line in
            total + terminalRowCount(for: line, width: width)
        }
    }

    private static func terminalRowCount(for line: String, width: Int) -> Int {
        let segments = line.components(separatedBy: .newlines)
        return segments.reduce(0) { total, segment in
            total + InputReader.wrappedLineCount(
                visibleLength: TerminalLayout.visibleLength(segment),
                width: width
            )
        }
    }

    private enum EscapeSequence {
        case up
        case down
        case pageUp
        case pageDown
        case cancelled
        case none
    }

    private static func readEscapeSequence() -> EscapeSequence {
        guard let first = readByte() else { return .cancelled }
        guard first == UInt8(ascii: "[") else { return .none }
        guard let second = readByte() else { return .none }
        switch second {
        case UInt8(ascii: "A"):
            return .up
        case UInt8(ascii: "B"):
            return .down
        case UInt8(ascii: "5"):
            _ = readByte()
            return .pageUp
        case UInt8(ascii: "6"):
            _ = readByte()
            return .pageDown
        default:
            return .none
        }
    }

    private static func finish(renderedLines: Int) {
        guard renderedLines > 0 else { return }
        print("\u{001B}[\(renderedLines)B", terminator: "")
        print("\r", terminator: "")
        fflush(stdout)
    }

    private static func clear(renderedLines: Int) {
        guard renderedLines > 0 else { return }
        print("\r", terminator: "")
        print("\u{001B}[J", terminator: "")
    }

    private static func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
    }

    private static func showCursor() {
        print("\u{001B}[?25h", terminator: "")
    }

    private static func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = read(pickerStdinFileDescriptor, &byte, 1)
        return count == 1 ? byte : nil
    }
}
