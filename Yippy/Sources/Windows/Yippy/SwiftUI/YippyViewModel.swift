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

enum CategoryFilter: Hashable, Identifiable {
    case all
    case category(HistoryItem.Metadata.Category)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .category(let category):
            return category.rawValue
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .category(let category):
            return category.displayName
        }
    }

    static var defaults: [CategoryFilter] {
        return [
            .all,
            .category(.text),
            .category(.code),
            .category(.photo),
            .category(.video),
            .category(.url),
            .category(.color),
            .category(.file),
            .category(.other)
        ]
    }
}

enum CodeSourceFilter: Hashable, Identifiable {
    case all
    case bundle(id: String, displayName: String)
    case unknown

    var id: String {
        switch self {
        case .all:
            return "all"
        case .bundle(let id, _):
            return id
        case .unknown:
            return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .all:
            return "All Apps"
        case .bundle(_, let displayName):
            return displayName
        case .unknown:
            return "Unknown App"
        }
    }
}

@Observable
class YippyViewModel {

    var searchBarValue: String = ""
    var itemCountLabel: String = ""
    var isSearchBarFocused: Bool = false
    
    var yippyHistory = YippyHistory(history: State.main.history, items: [])

    private var searchEngine = SearchEngine(data: [])
    private let disposeBag = DisposeBag()

    var isPreviewShowing = false

    var panelPosition: Axis.Set = .vertical

    var itemGroups = BehaviorRelay<[String]>(value: ["Clipboard", "Favourites", "Clipboard", "Favourites", "Clipboard", "Favourites"])

    var categoryFilters: [CategoryFilter] = CategoryFilter.defaults
    var selectedCategoryFilter: CategoryFilter = .all
    var codeSourceFilters: [CodeSourceFilter] = [.all]
    var selectedCodeSourceFilter: CodeSourceFilter = .all

    var shouldShowCodeSourceFilters: Bool {
        switch selectedCategoryFilter {
        case .category(let category):
            return category == .code && codeSourceFilters.count > 1
        default:
            return false
        }
    }
    
    var isRichText = Settings.main.showsRichText
    
    private(set) var selectedItem: HistoryItem?
    
    private let results = BehaviorRelay(value: Results(items: [], isSearchResult: false))
    private let selected = BehaviorRelay<Int?>(value: nil)
    
    func onAppear() {
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
        
        // Paste hot keys
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
    }
    
    func resetSelected() {
        if yippyHistory.items.count > 0 {
            selected.accept(0)
        }
        else {
            selected.accept(nil)
        }
    }
    
    func onHistoryChange(_ history: [HistoryItem], change: History.Change) {
        updateSearchEngine(items: history)
        refreshCodeSources(from: history)

        if !searchBarValue.isEmpty {
            runSearch(resetSelection: false)
        }
        else {
            let filteredHistory = applyFilters(to: history)
            publishResults(items: filteredHistory, isSearchResult: false, resetSelection: false)
            switch change {
            case .insert(let i):
                if i == 0, let newestItem = history.first, let firstFilteredItem = filteredHistory.first, newestItem === firstFilteredItem {
                    incrementSelected()
                }
                break;
            default: break;
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
    }
    
    func updateSearchEngine(items: [HistoryItem]) {
        self.searchEngine = SearchEngine(data: items.compactMap({$0.getPlainString()}))
    }

    func onAllChange(_ results: Results, _ selected: (Int?, Int?)) {
        if results.items != self.yippyHistory.items {
            if results.isSearchResult {
                self.itemCountLabel = "\(results.items.count) matches"
            }
            else {
                self.itemCountLabel = "\(results.items.count) items"
            }
            
            self.yippyHistory = YippyHistory(history: State.main.history, items: results.items)
        }
        
        if let selectedIndex = selected.1, yippyHistory.items.indices.contains(selectedIndex) {
            self.selectedItem = yippyHistory.items[selectedIndex]
            
            if self.isPreviewShowing {
                State.main.previewHistoryItem.accept(self.yippyHistory.items[selectedIndex])
            }
        }
    }
    
    func onShowsRichText(_ showsRichText: Bool) {
        isRichText = showsRichText
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
            if isPreviewShowing {
                State.main.previewHistoryItem.accept(yippyHistory.items[selected])
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
    
    func runSearch(resetSelection: Bool = true) {
        searchEngine.search(query: self.searchBarValue, completion: { result in
            if (result.query.query.isEmpty) {
                let filteredItems = self.applyFilters(to: State.main.history.items)
                self.publishResults(items: filteredItems, isSearchResult: false, resetSelection: resetSelection)
                return
            }

            var filteredData = [HistoryItem]()
            for i in result.results {
                if State.main.history.items.indices.contains(i) {
                    filteredData.append(State.main.history.items[i])
                }
            }

            let filteredItems = self.applyFilters(to: filteredData)
            self.publishResults(items: filteredItems, isSearchResult: true, resetSelection: resetSelection)
        })
    }

    func selectCategory(_ filter: CategoryFilter) {
        guard selectedCategoryFilter != filter else { return }
        selectedCategoryFilter = filter
        if case .category(let category) = filter, category == .code {
            // keep existing code source selection
        }
        else {
            selectedCodeSourceFilter = .all
        }
        updateFilteredResults(resetSelection: true)
    }

    func selectCodeSource(_ filter: CodeSourceFilter) {
        guard selectedCodeSourceFilter != filter else { return }
        selectedCodeSourceFilter = filter
        updateFilteredResults(resetSelection: true)
    }
    
    private func incrementSelected() {
        guard let s = selected.value else {
            if yippyHistory.items.count > 0 {
                selected.accept(0)
            }
            return
        }
        if s < yippyHistory.items.count - 1 {
            selected.accept(s + 1)
        }
    }
    
    private func decrementSelected() {
        guard let s = selected.value else {
            if yippyHistory.items.count > 0 {
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

    private func applyFilters(to items: [HistoryItem]) -> [HistoryItem] {
        var filtered = items

        switch selectedCategoryFilter {
        case .all:
            break
        case .category(let category):
            filtered = filtered.filter { $0.category == category }
        }

        if selectedCategoryFilter == .category(.code) {
            switch selectedCodeSourceFilter {
            case .all:
                break
            case .bundle(let id, _):
                filtered = filtered.filter { $0.originBundleId == id }
            case .unknown:
                filtered = filtered.filter { $0.originBundleId == nil }
            }
        }

        return filtered
    }

    private func refreshCodeSources(from items: [HistoryItem]) {
        let codeItems = items.filter { $0.category == .code }
        var uniqueBundles = Set<String>()
        var filters: [CodeSourceFilter] = [.all]
        var hasUnknown = false

        for item in codeItems {
            if let bundleId = item.originBundleId {
                if uniqueBundles.insert(bundleId).inserted {
                    let displayName = item.originApplicationName ?? item.sourceDisplayName
                    filters.append(.bundle(id: bundleId, displayName: displayName))
                }
            } else {
                hasUnknown = true
            }
        }

        if hasUnknown {
            filters.append(.unknown)
        }

        codeSourceFilters = filters
        if !codeSourceFilters.contains(selectedCodeSourceFilter) {
            selectedCodeSourceFilter = .all
        }
    }

    private func publishResults(items: [HistoryItem], isSearchResult: Bool, resetSelection: Bool) {
        results.accept(Results(items: items, isSearchResult: isSearchResult))
        if resetSelection {
            DispatchQueue.main.async {
                self.resetSelected()
            }
        }
    }

    private func updateFilteredResults(resetSelection: Bool) {
        if searchBarValue.isEmpty {
            let filtered = applyFilters(to: State.main.history.items)
            publishResults(items: filtered, isSearchResult: false, resetSelection: resetSelection)
        } else {
            runSearch(resetSelection: resetSelection)
        }
    }
}
