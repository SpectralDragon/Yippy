//
//  YippyViewModel.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import Cocoa
import HotKey
import RxSwift
import RxRelay
import RxCocoa
import SwiftUI
import Observation

struct Results {
    let items: [HistoryItem]
    let isSearchResult: Bool
}

struct TimelineSection: Identifiable {
    let id: String
    let title: String?
    let items: [HistoryItem]
}

enum HistoryRowContentKind {
    case fileThumbnail
    case fileIcon
    case text
    case image
    case color
    case webLink
}

struct HistoryRowSnapshot {
    let id: UUID
    let contentKind: HistoryRowContentKind
    let category: HistoryItemCategory
    let codeSource: CodeSource?
    let title: String
    let subtitle: String?
    let chips: [String]
    let relativeTime: String?
    let previewText: NSAttributedString?
    let previewImage: NSImage?
    let previewImageSize: NSSize?
    let displayPath: NSAttributedString?
    let colorValue: NSColor?
    let linkURL: URL?
    let isLoading: Bool
}

final class HistoryPreviewPrefetcher {
    private let queue: OperationQueue
    private let lock = NSLock()
    private var pendingIDs = Set<UUID>()

    init(maxConcurrentOperations: Int = 2) {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperations
        queue.qualityOfService = .userInitiated
    }

    func prefetch(
        itemID: UUID,
        generation: Int,
        builder: @escaping () -> HistoryRowSnapshot,
        completion: @escaping (UUID, Int, HistoryRowSnapshot) -> Void
    ) {
        lock.lock()
        if pendingIDs.contains(itemID) {
            lock.unlock()
            return
        }
        pendingIDs.insert(itemID)
        lock.unlock()

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            defer {
                self?.lock.lock()
                self?.pendingIDs.remove(itemID)
                self?.lock.unlock()
            }

            guard let operation, !operation.isCancelled else {
                return
            }

            let snapshot = builder()
            guard !operation.isCancelled else {
                return
            }

            OperationQueue.main.addOperation {
                if !operation.isCancelled {
                    completion(itemID, generation, snapshot)
                }
            }
        }
        queue.addOperation(operation)
    }

    func cancelAll() {
        queue.cancelAllOperations()
        lock.lock()
        pendingIDs.removeAll()
        lock.unlock()
    }
}

private enum TimelineBucket: String, CaseIterable {
    case today
    case yesterday
    case earlier
    case undated

    var title: String? {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .earlier:
            return "Earlier"
        case .undated:
            return nil
        }
    }
}

@Observable
class YippyViewModel {

    var searchBarValue: String = ""
    var itemCountLabel: String = ""
    var isSearchBarFocused: Bool = false

    var selectedCategory: HistoryItemCategory? = nil

    var yippyHistory = YippyHistory(history: State.main.history, items: [])
    var visibleItems = [HistoryItem]()
    var rowSnapshots = [UUID: HistoryRowSnapshot]()

    private var allResultItems = [HistoryItem]()
    private var searchEngine = SearchEngine(data: [])
    private let disposeBag = DisposeBag()
    private let previewPrefetcher: HistoryPreviewPrefetcher

    var isPreviewShowing = false

    var panelPosition: Axis.Set = .vertical

    var itemGroups = BehaviorRelay<[String]>(value: ["Clipboard", "Favourites", "Clipboard", "Favourites", "Clipboard", "Favourites"])

    var isRichText = Settings.main.showsRichText

    private(set) var selectedItem: HistoryItem?
    private(set) var scrollToTopRequest = UUID()

    private let results = BehaviorRelay(value: Results(items: [], isSearchResult: false))
    private let selected = BehaviorRelay<Int?>(value: nil)
    private let notificationCenter: NotificationCenter
    private let currentDate: () -> Date
    private let backgroundResetThreshold: TimeInterval

    private var hiddenAt: Date?
    private var appInactiveAt: Date?
    private var didSetupBackgroundObservers = false
    private var snapshotGeneration = 0

    let initialPageSize: Int
    let pageSize: Int
    let prefetchThreshold: Int

    var timelineSections: [TimelineSection] {
        buildTimelineSections(from: visibleItems)
    }

    var hasItems: Bool {
        !visibleItems.isEmpty
    }

    init(
        notificationCenter: NotificationCenter = .default,
        backgroundResetThreshold: TimeInterval = 30,
        currentDate: @escaping () -> Date = Date.init,
        initialPageSize: Int = 40,
        pageSize: Int = 30,
        prefetchThreshold: Int = 12,
        previewPrefetcher: HistoryPreviewPrefetcher = HistoryPreviewPrefetcher()
    ) {
        self.notificationCenter = notificationCenter
        self.backgroundResetThreshold = backgroundResetThreshold
        self.currentDate = currentDate
        self.initialPageSize = initialPageSize
        self.pageSize = pageSize
        self.prefetchThreshold = prefetchThreshold
        self.previewPrefetcher = previewPrefetcher
    }

    func onAppear() {
        setupBackgroundObserversIfNeeded()
        State.main.history.subscribe(onNext: onHistoryChange)

        State.main.panelPosition.subscribe(onNext: onWindowPanelPositionChanged).disposed(by: disposeBag)

        State.main.showsRichText.distinctUntilChanged().subscribe(onNext: onShowsRichText).disposed(by: disposeBag)

        Observable.combineLatest(
            results,
            selected.distinctUntilChanged().withPrevious(startWith: nil)
        )
        .observe(on: MainScheduler.instance)
        .subscribe(onNext: onAllChange)
        .disposed(by: disposeBag)

        // TODO: Fix hack to make onAllChange run initially
        selected.accept(1)
        resetSelected()

        YippyHotKeys.downArrow.onDown(goToNextItem)
        YippyHotKeys.downArrow.onLong(goToNextItem)
        YippyHotKeys.pageDown.onDown(goToNextItem)
        YippyHotKeys.pageDown.onLong(goToNextItem)
        YippyHotKeys.upArrow.onDown(goToPreviousItem)
        YippyHotKeys.upArrow.onLong(goToPreviousItem)
        YippyHotKeys.pageUp.onDown(goToPreviousItem)
        YippyHotKeys.pageUp.onLong(goToPreviousItem)
        YippyHotKeys.escape.onDown(close)
        YippyHotKeys.return.onDown(pasteSelected)
        YippyHotKeys.ctrlAltCmdLeftArrow.onDown { State.main.panelPosition.accept(.left) }
        YippyHotKeys.ctrlAltCmdRightArrow.onDown { State.main.panelPosition.accept(.right) }
        YippyHotKeys.ctrlAltCmdDownArrow.onDown { State.main.panelPosition.accept(.bottom) }
        YippyHotKeys.ctrlAltCmdUpArrow.onDown { State.main.panelPosition.accept(.top) }
        YippyHotKeys.ctrlDelete.onDown(deleteSelected)
        YippyHotKeys.space.onDown(togglePreview)
        YippyHotKeys.cmdBackslash.onDown(focusSearchBar)
        YippyHotKeys.cmdV.onDown(pasteSelected)

        YippyHotKeys.cmd0.onDown { self.shortcutPressed(key: 0) }
        YippyHotKeys.cmd1.onDown { self.shortcutPressed(key: 1) }
        YippyHotKeys.cmd2.onDown { self.shortcutPressed(key: 2) }
        YippyHotKeys.cmd3.onDown { self.shortcutPressed(key: 3) }
        YippyHotKeys.cmd4.onDown { self.shortcutPressed(key: 4) }
        YippyHotKeys.cmd5.onDown { self.shortcutPressed(key: 5) }
        YippyHotKeys.cmd6.onDown { self.shortcutPressed(key: 6) }
        YippyHotKeys.cmd7.onDown { self.shortcutPressed(key: 7) }
        YippyHotKeys.cmd8.onDown { self.shortcutPressed(key: 8) }
        YippyHotKeys.cmd9.onDown { self.shortcutPressed(key: 9) }

        bindHotKeyToYippyWindow(YippyHotKeys.downArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.upArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.return, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.escape, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.pageDown, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.pageUp, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdLeftArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdRightArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdDownArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlAltCmdUpArrow, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd0, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd1, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd2, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd3, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd4, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd5, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd6, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd7, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd8, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmd9, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.ctrlDelete, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.space, disposeBag: disposeBag)
        bindHotKeyToYippyWindow(YippyHotKeys.cmdV, disposeBag: disposeBag)
    }

    func resetSelected() {
        if allResultItems.count > 0 {
            selected.accept(0)
        }
        else {
            selected.accept(nil)
        }
    }

    func resetVisibleWindow() {
        let count = min(initialPageSize, allResultItems.count)
        visibleItems = Array(allResultItems.prefix(count))
        invalidateSnapshots()
        prefetchVisibleSnapshots()
    }

    func loadNextPageIfNeeded(currentItemID: UUID) {
        guard let currentVisibleIndex = visibleItems.firstIndex(where: { $0.id == currentItemID }) else {
            return
        }

        let remaining = visibleItems.count - currentVisibleIndex - 1
        guard remaining <= prefetchThreshold else {
            prepareRowIfNeeded(for: currentItemID)
            return
        }

        let nextCount = min(allResultItems.count, visibleItems.count + pageSize)
        guard nextCount > visibleItems.count else {
            prepareRowIfNeeded(for: currentItemID)
            return
        }

        visibleItems = Array(allResultItems.prefix(nextCount))
        prefetchVisibleSnapshots()
        prepareRowIfNeeded(for: currentItemID)
    }

    func ensureSelectionVisible() {
        guard let selectedIndex = selected.value else { return }
        ensureSelectionVisible(index: selectedIndex)
    }

    func onHistoryChange(_ history: [HistoryItem], change: History.Change) {
        updateSearchEngine(items: history)
        if !searchBarValue.isEmpty {
            runSearch()
        }
        else {
            let filteredItems = applyCategoryFilter(to: history)
            results.accept(Results(items: filteredItems, isSearchResult: false))
            switch change {
            case .insert(let i):
                if i == 0 {
                    incrementSelected()
                }
            default:
                break
            }
        }
    }

    func onWindowPanelPositionChanged(_ position: PanelPosition) {
        switch position {
        case .right, .left:
            panelPosition = .vertical
        case .top, .bottom:
            panelPosition = .horizontal
        default:
            panelPosition = .vertical
        }
        resetVisibleWindow()
    }

    func updateSearchEngine(items: [HistoryItem]) {
        self.searchEngine = SearchEngine(data: items.compactMap({ $0.getPlainString() }))
    }

    func onAllChange(_ results: Results, _ selected: (Int?, Int?)) {
        if results.items != allResultItems {
            if results.isSearchResult {
                self.itemCountLabel = "\(results.items.count) matches"
            }
            else {
                self.itemCountLabel = "\(results.items.count) items"
            }

            self.allResultItems = results.items
            self.yippyHistory = YippyHistory(history: State.main.history, items: results.items)
            resetVisibleWindow()
        }

        if let selectedIndex = selected.1, allResultItems.indices.contains(selectedIndex) {
            ensureSelectionVisible(index: selectedIndex)
            let item = allResultItems[selectedIndex]
            self.selectedItem = item
            prefetchSnapshots(around: selectedIndex)

            if self.isPreviewShowing {
                State.main.previewHistoryItem.accept(item)
            }
        } else {
            self.selectedItem = nil
        }
    }

    func onShowsRichText(_ showsRichText: Bool) {
        isRichText = showsRichText
        invalidateSnapshots()
        prefetchVisibleSnapshots()
    }

    func bindHotKeyToYippyWindow(_ hotKey: YippyHotKey, disposeBag: DisposeBag) {
        State.main.isHistoryPanelShown
            .distinctUntilChanged()
            .subscribe(onNext: { [] in
                hotKey.isPaused = !$0
            })
            .disposed(by: disposeBag)
    }

    func goToNextItem() {
        incrementSelected()
    }

    func goToPreviousItem() {
        decrementSelected()
    }

    func pasteSelected() {
        if let selected = self.selected.value {
            paste(selected: selected)
        }
    }

    func deleteSelected() {
        if let selected = self.selected.value {
            self.selected.accept(yippyHistory.delete(selected: selected))
        }
    }

    func paste(at index: Int) {
        paste(selected: index)
    }

    func delete(at index: Int) {
        self.selected.accept(yippyHistory.delete(selected: index))
    }

    func onSelectItem(at index: Int) {
        self.selected.accept(index)
    }

    func index(for item: HistoryItem) -> Int? {
        allResultItems.firstIndex(of: item)
    }

    func snapshot(for item: HistoryItem) -> HistoryRowSnapshot {
        rowSnapshots[item.id] ?? makePlaceholderSnapshot(for: item, isLoading: true)
    }

    func prepareRowIfNeeded(for itemID: UUID) {
        guard let item = allResultItems.first(where: { $0.id == itemID }) else { return }
        if rowSnapshots[item.id] == nil {
            rowSnapshots[item.id] = makePlaceholderSnapshot(for: item, isLoading: true)
        }
        prefetchSnapshot(for: item)
    }

    func buildTimelineSections(from items: [HistoryItem]) -> [TimelineSection] {
        var groupedItems = Dictionary(uniqueKeysWithValues: TimelineBucket.allCases.map { ($0, [HistoryItem]()) })

        for item in items {
            groupedItems[bucket(for: item.createdAt), default: []].append(item)
        }

        return TimelineBucket.allCases.compactMap { bucket in
            guard let bucketItems = groupedItems[bucket], !bucketItems.isEmpty else {
                return nil
            }
            return TimelineSection(id: bucket.rawValue, title: bucket.title, items: bucketItems)
        }
    }

    func relativeTimestampLabel(for item: HistoryItem) -> String? {
        guard let date = item.createdAt else { return nil }
        let seconds = max(0, Int(currentDate().timeIntervalSince(date)))

        if seconds < 60 {
            return "now"
        }
        if seconds < 3600 {
            return "\(max(1, seconds / 60))m ago"
        }
        if seconds < 86_400 {
            return "\(max(1, seconds / 3600))h ago"
        }
        if Calendar.autoupdatingCurrent.isDateInYesterday(date) {
            return "Yesterday"
        }
        if seconds < 604_800 {
            return "\(max(1, seconds / 86_400))d ago"
        }

        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    func titleText(for item: HistoryItem) -> String {
        if let fileURL = item.getFileUrl() {
            return fileURL.lastPathComponent
        }

        if let url = item.getUrl() {
            return url.host ?? url.absoluteString
        }

        if let text = compactTextPreview(for: item), !text.isEmpty {
            return text
        }

        if let color = item.getColor() {
            return color.hexString
        }

        if item.getImage() != nil {
            return "Image copied"
        }

        return item.getCategory().displayName
    }

    func bodyText(for item: HistoryItem) -> String? {
        if item.content == .text || item.content == .webLink {
            return nil
        }

        if let fileURL = item.getFileUrl() {
            let parentPath = fileURL.deletingLastPathComponent().path
            return parentPath.isEmpty ? nil : parentPath
        }

        if let url = item.getUrl() {
            return url.absoluteString
        }

        if let image = item.getImage() {
            return "\(Int(image.size.width)) x \(Int(image.size.height)) px"
        }

        if let text = compactBodyPreview(for: item), !text.isEmpty {
            return text
        }

        return nil
    }

    func chipTexts(for item: HistoryItem) -> [String] {
        var chips = [String]()

        if let source = sourceApplicationName(for: item), !source.isEmpty {
            chips.append(source)
        }

        if let codeSource = item.getCodeSource(), codeSource != .unknown {
            chips.append(codeSource.displayName)
        }

        let categoryName = item.getCategory().displayName
        if chips.last != categoryName {
            chips.append(categoryName)
        }

        return Array(chips.prefix(3))
    }

    func close() {
        isPreviewShowing = false
        State.main.isHistoryPanelShown.accept(false)
        State.main.previewHistoryItem.accept(nil)
        resetSelected()
    }

    func shortcutPressed(key: Int) {
        paste(selected: key)
    }

    func togglePreview() {
        if let selected = self.selected.value {
            isPreviewShowing = !isPreviewShowing
            if isPreviewShowing, allResultItems.indices.contains(selected) {
                State.main.previewHistoryItem.accept(allResultItems[selected])
            }
            else {
                State.main.previewHistoryItem.accept(nil)
            }
        }
    }

    func focusSearchBar() {
        NSApp.activate(ignoringOtherApps: true)
        self.isSearchBarFocused = true
    }

    func runSearch() {
        searchEngine.search(query: self.searchBarValue, completion: { result in
            if result.query.query.isEmpty {
                let filteredItems = self.applyCategoryFilter(to: State.main.history.items)
                self.results.accept(Results(items: filteredItems, isSearchResult: false))
                return
            }

            var filteredData = [HistoryItem]()
            for i in result.results {
                filteredData.append(State.main.history.items[i])
            }

            let categoryFilteredData = self.applyCategoryFilter(to: filteredData)
            self.results.accept(Results(items: categoryFilteredData, isSearchResult: true))
        })
    }

    func applyCategoryFilter(to items: [HistoryItem]) -> [HistoryItem] {
        guard let selectedCategory = selectedCategory else {
            return items
        }

        return items.filter { item in
            item.getCategory() == selectedCategory
        }
    }

    func getAvailableCategories() -> [HistoryItemCategory] {
        let allCategories = Set(State.main.history.items.map { $0.getCategory() })
        return Array(allCategories).sorted { $0.displayName < $1.displayName }
    }

    func getCategoryCount(for category: HistoryItemCategory) -> Int {
        return State.main.history.items.filter { $0.getCategory() == category }.count
    }

    func onCategorySelected(_ category: HistoryItemCategory?) {
        selectedCategory = category
        if searchBarValue.isEmpty {
            let filteredItems = applyCategoryFilter(to: State.main.history.items)
            results.accept(Results(items: filteredItems, isSearchResult: false))
        } else {
            runSearch()
        }
    }

    func onHistoryPanelVisibilityChanged(_ isShown: Bool) {
        if isShown {
            defer { hiddenAt = nil }
            resetVisibleWindow()
            if shouldResetScroll(since: hiddenAt) {
                requestScrollToTop()
            }
            return
        }

        hiddenAt = currentDate()
    }

    func onApplicationDidResignActive() {
        appInactiveAt = currentDate()
    }

    func onApplicationDidBecomeActive() {
        defer { appInactiveAt = nil }

        guard State.main.isHistoryPanelShown.value else { return }

        if shouldResetScroll(since: appInactiveAt) {
            requestScrollToTop()
        }
    }

    private func prefetchVisibleSnapshots() {
        guard !allResultItems.isEmpty else { return }
        let upperBound = min(allResultItems.count, visibleItems.count + prefetchThreshold)
        for item in allResultItems.prefix(upperBound) {
            if rowSnapshots[item.id] == nil {
                rowSnapshots[item.id] = makePlaceholderSnapshot(for: item, isLoading: true)
            }
            prefetchSnapshot(for: item)
        }
    }

    private func prefetchSnapshots(around index: Int) {
        guard allResultItems.indices.contains(index) else { return }
        let upperBound = min(allResultItems.count, index + prefetchThreshold + 1)
        for item in allResultItems[index..<upperBound] {
            if rowSnapshots[item.id] == nil {
                rowSnapshots[item.id] = makePlaceholderSnapshot(for: item, isLoading: true)
            }
            prefetchSnapshot(for: item)
        }
    }

    private func invalidateSnapshots() {
        snapshotGeneration += 1
        previewPrefetcher.cancelAll()
        rowSnapshots.removeAll()
    }

    private func prefetchSnapshot(for item: HistoryItem) {
        let generation = snapshotGeneration
        previewPrefetcher.prefetch(
            itemID: item.id,
            generation: generation,
            builder: { [weak self] in
                guard let self else {
                    return HistoryRowSnapshot(
                        id: item.id,
                        contentKind: .text,
                        category: item.getCategory(),
                        codeSource: item.getCodeSource(),
                        title: item.getCategory().displayName,
                        subtitle: nil,
                        chips: [],
                        relativeTime: nil,
                        previewText: nil,
                        previewImage: nil,
                        previewImageSize: nil,
                        displayPath: nil,
                        colorValue: nil,
                        linkURL: nil,
                        isLoading: false
                    )
                }
                return self.buildLoadedSnapshot(for: item)
            },
            completion: { [weak self] itemID, generation, snapshot in
                guard let self, generation == self.snapshotGeneration else { return }
                self.rowSnapshots[itemID] = snapshot
            }
        )
    }

    private func buildLoadedSnapshot(for item: HistoryItem) -> HistoryRowSnapshot {
        let category = item.getCategory()
        let codeSource = item.getCodeSource()
        let chips = chipTexts(for: item)
        let relativeTime = relativeTimestampLabel(for: item)

        switch lightweightContentKind(for: item) {
        case .fileThumbnail:
            let url = item.getFileUrl()
            let title = url?.lastPathComponent ?? "File copied"
            let subtitle = url?.deletingLastPathComponent().path
            let displayPath = url.map { formatFileUrl($0) }
            let thumbnail = item.getThumbnailImage()
            let fileIcon = thumbnail == nil ? item.getFileIcon() : nil
            let contentKind: HistoryRowContentKind = thumbnail == nil ? .fileIcon : .fileThumbnail
            let image = thumbnail ?? fileIcon
            return HistoryRowSnapshot(
                id: item.id,
                contentKind: contentKind,
                category: category,
                codeSource: codeSource,
                title: title,
                subtitle: subtitle?.isEmpty == true ? nil : subtitle,
                chips: chips,
                relativeTime: relativeTime,
                previewText: nil,
                previewImage: image,
                previewImageSize: image?.size,
                displayPath: displayPath,
                colorValue: nil,
                linkURL: nil,
                isLoading: false
            )

        case .webLink:
            let url = item.getUrl()
            let urlString = url?.absoluteString ?? "URL copied"
            return HistoryRowSnapshot(
                id: item.id,
                contentKind: .webLink,
                category: category,
                codeSource: codeSource,
                title: url?.host ?? urlString,
                subtitle: urlString,
                chips: chips,
                relativeTime: relativeTime,
                previewText: NSAttributedString(
                    string: urlString,
                    attributes: HistoryItemText.itemStringAttributes
                ),
                previewImage: nil,
                previewImageSize: nil,
                displayPath: nil,
                colorValue: nil,
                linkURL: url,
                isLoading: false
            )

        case .color:
            let color = item.getColor()?.withAlphaComponent(1)
            let title = color?.hexString ?? "Color"
            return HistoryRowSnapshot(
                id: item.id,
                contentKind: .color,
                category: category,
                codeSource: codeSource,
                title: title,
                subtitle: nil,
                chips: chips,
                relativeTime: relativeTime,
                previewText: NSAttributedString(
                    string: title,
                    attributes: HistoryItemText.itemStringAttributes
                ),
                previewImage: nil,
                previewImageSize: nil,
                displayPath: nil,
                colorValue: color,
                linkURL: nil,
                isLoading: false
            )

        case .image:
            let image = item.getImage()
            let subtitle = image.map { "\(Int($0.size.width)) x \(Int($0.size.height)) px" }
            return HistoryRowSnapshot(
                id: item.id,
                contentKind: .image,
                category: category,
                codeSource: codeSource,
                title: "Image copied",
                subtitle: subtitle,
                chips: chips,
                relativeTime: relativeTime,
                previewText: nil,
                previewImage: image,
                previewImageSize: image?.size,
                displayPath: nil,
                colorValue: nil,
                linkURL: nil,
                isLoading: false
            )

        case .text:
            let textPreview = HistoryItemText.getAttributedString(forItem: item, usingItemRtf: isRichText)
            return HistoryRowSnapshot(
                id: item.id,
                contentKind: .text,
                category: category,
                codeSource: codeSource,
                title: compactTextPreview(for: item) ?? category.displayName,
                subtitle: compactBodyPreview(for: item),
                chips: chips,
                relativeTime: relativeTime,
                previewText: textPreview,
                previewImage: nil,
                previewImageSize: nil,
                displayPath: nil,
                colorValue: nil,
                linkURL: nil,
                isLoading: false
            )

        case .fileIcon:
            return makePlaceholderSnapshot(for: item, isLoading: false)
        }
    }

    private func makePlaceholderSnapshot(for item: HistoryItem, isLoading: Bool) -> HistoryRowSnapshot {
        let category = item.getCategory()
        let codeSource = item.getCodeSource()
        let chips = chipTexts(for: item)
        let relativeTime = relativeTimestampLabel(for: item)

        let title: String
        switch lightweightContentKind(for: item) {
        case .fileThumbnail, .fileIcon:
            title = "File copied"
        case .image:
            title = "Image copied"
        case .webLink:
            title = "URL copied"
        case .color:
            title = "Color copied"
        case .text:
            title = category.displayName
        }

        return HistoryRowSnapshot(
            id: item.id,
            contentKind: lightweightContentKind(for: item),
            category: category,
            codeSource: codeSource,
            title: title,
            subtitle: nil,
            chips: chips,
            relativeTime: relativeTime,
            previewText: nil,
            previewImage: nil,
            previewImageSize: nil,
            displayPath: nil,
            colorValue: nil,
            linkURL: nil,
            isLoading: isLoading
        )
    }

    private func lightweightContentKind(for item: HistoryItem) -> HistoryRowContentKind {
        if item.types.contains(.fileURL) {
            return .fileThumbnail
        }
        if item.types.contains(.URL) {
            return .webLink
        }
        if item.types.contains(.color) {
            return .color
        }
        if item.types.contains(.tiff) || item.types.contains(.png) {
            return .image
        }
        return .text
    }

    private func ensureSelectionVisible(index: Int) {
        guard allResultItems.indices.contains(index) else { return }
        if visibleItems.count > index {
            return
        }

        let requiredCount = min(
            allResultItems.count,
            max(index + 1, visibleItems.count + pageSize)
        )
        visibleItems = Array(allResultItems.prefix(requiredCount))
        prefetchVisibleSnapshots()
    }

    private func bucket(for date: Date?) -> TimelineBucket {
        guard let date else {
            return .undated
        }

        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        return .earlier
    }

    private func compactTextPreview(for item: HistoryItem) -> String? {
        let text = item.getPlainString()?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let text else { return nil }
        return ellipsize(text, limit: 72)
    }

    private func compactBodyPreview(for item: HistoryItem) -> String? {
        guard let text = item.getPlainString() else {
            return nil
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        let body = lines.dropFirst().joined(separator: " ")
        if !body.isEmpty {
            return ellipsize(body, limit: 120)
        }

        let firstLine = lines[0]
        if firstLine.count > 72 {
            return ellipsize(firstLine, limit: 140)
        }

        return nil
    }

    private func ellipsize(_ string: String, limit: Int) -> String {
        guard string.count > limit else {
            return string
        }
        return String(string.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func sourceApplicationName(for item: HistoryItem) -> String? {
        guard let bundleID = item.metadata?.originBundleId ?? item.originBundleId else {
            return nil
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let bundle = Bundle(url: appURL)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    private func incrementSelected() {
        guard let s = selected.value else {
            if allResultItems.count > 0 {
                selected.accept(0)
            }
            return
        }
        if s < allResultItems.count - 1 {
            let next = s + 1
            ensureSelectionVisible(index: next)
            selected.accept(next)
        }
    }

    private func decrementSelected() {
        guard let s = selected.value else {
            if allResultItems.count > 0 {
                selected.accept(0)
            }
            return
        }
        if s > 0 {
            selected.accept(s - 1)
        }
    }

    private func paste(selected: Int) {
        self.close()
        yippyHistory.paste(selected: selected)
    }

    private func setupBackgroundObserversIfNeeded() {
        guard !didSetupBackgroundObservers else { return }
        didSetupBackgroundObservers = true

        State.main.isHistoryPanelShown
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: onHistoryPanelVisibilityChanged)
            .disposed(by: disposeBag)

        notificationCenter.rx.notification(NSApplication.didResignActiveNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                self?.onApplicationDidResignActive()
            })
            .disposed(by: disposeBag)

        notificationCenter.rx.notification(NSApplication.didBecomeActiveNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                self?.onApplicationDidBecomeActive()
            })
            .disposed(by: disposeBag)
    }

    private func shouldResetScroll(since date: Date?) -> Bool {
        guard let date else { return false }
        return currentDate().timeIntervalSince(date) >= backgroundResetThreshold
    }

    private func requestScrollToTop() {
        guard !visibleItems.isEmpty else { return }

        resetSelected()
        scrollToTopRequest = UUID()
    }
}

private extension NSColor {
    var hexString: String {
        guard let color = usingColorSpace(.deviceRGB) else {
            return "Color"
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
