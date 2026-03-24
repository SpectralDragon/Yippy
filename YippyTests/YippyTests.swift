//
//  YippyTests.swift
//  YippyTests
//
//  Created by Matthew Davidson on 26/7/19.
//  Copyright © 2019 MatthewDavidson. All rights reserved.
//

import XCTest
@testable import Yippy

class YippyTests: XCTestCase {
    func testHistoryItemMetadataDecodesLegacyDetectedAt() throws {
        let legacyDate = Date(timeIntervalSince1970: 1_710_000_000)
        struct LegacyMetadata: Codable {
            let category: HistoryItemCategory
            let detectedAt: Date
            let originBundleId: String
        }

        let json = try JSONEncoder().encode(
            LegacyMetadata(
                category: .text,
                detectedAt: legacyDate,
                originBundleId: "com.apple.TextEdit"
            )
        )

        let metadata = try JSONDecoder().decode(HistoryItemMetadata.self, from: json)

        XCTAssertEqual(metadata.category, .text)
        XCTAssertEqual(metadata.createdAt?.timeIntervalSince1970, legacyDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(metadata.originBundleId, "com.apple.TextEdit")
    }

    func testTimelineSectionsGroupTodayYesterdayEarlierAndUndated() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let viewModel = YippyViewModel(currentDate: { now })

        let items = [
            makeHistoryItem(text: "Today", category: .text, createdAt: now.addingTimeInterval(-120)),
            makeHistoryItem(text: "Yesterday", category: .text, createdAt: now.addingTimeInterval(-90_000)),
            makeHistoryItem(text: "Earlier", category: .text, createdAt: now.addingTimeInterval(-800_000)),
            makeHistoryItem(text: "Undated", category: .text, createdAt: nil)
        ]

        let sections = viewModel.buildTimelineSections(from: items)

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Earlier", nil])
        XCTAssertEqual(sections.map(\.items.count), [1, 1, 1, 1])
    }

    func testRelativeTimestampLabelsUseShortUnitsAndDateFallback() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let viewModel = YippyViewModel(currentDate: { now })

        XCTAssertEqual(viewModel.relativeTimestampLabel(for: makeHistoryItem(text: "Recent", category: .text, createdAt: now.addingTimeInterval(-90))), "1m ago")
        XCTAssertEqual(viewModel.relativeTimestampLabel(for: makeHistoryItem(text: "Hours", category: .text, createdAt: now.addingTimeInterval(-7_200))), "2h ago")
        XCTAssertNotNil(viewModel.relativeTimestampLabel(for: makeHistoryItem(text: "Old", category: .text, createdAt: now.addingTimeInterval(-900_000))))
    }

    func testCategoryFilterKeepsTimelineGroupingStable() {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let viewModel = YippyViewModel(currentDate: { now })
        let items = [
            makeHistoryItem(text: "Text", category: .text, createdAt: now.addingTimeInterval(-60)),
            makeHistoryItem(text: "Code", category: .code, createdAt: now.addingTimeInterval(-120))
        ]

        viewModel.selectedCategory = .code

        let filtered = viewModel.applyCategoryFilter(to: items)
        let sections = viewModel.buildTimelineSections(from: filtered)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.getCategory(), .code)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.items.count, 1)
    }

    func testVisibleWindowStartsWithInitialPageSize() {
        let viewModel = YippyViewModel()
        let items = makeHistoryItems(count: 120)

        viewModel.onAllChange(Results(items: items, isSearchResult: false), (nil, nil))

        XCTAssertEqual(viewModel.visibleItems.count, 40)
        XCTAssertEqual(viewModel.visibleItems.first?.id, items.first?.id)
        XCTAssertEqual(viewModel.visibleItems.last?.id, items[39].id)
    }

    func testLoadNextPageWhenApproachingThreshold() {
        let viewModel = YippyViewModel()
        let items = makeHistoryItems(count: 120)

        viewModel.onAllChange(Results(items: items, isSearchResult: false), (nil, nil))
        viewModel.loadNextPageIfNeeded(currentItemID: items[28].id)

        XCTAssertEqual(viewModel.visibleItems.count, 70)
        XCTAssertEqual(viewModel.visibleItems.last?.id, items[69].id)
    }

    func testResultsChangeResetsVisibleWindowToFirstPage() {
        let viewModel = YippyViewModel()
        let items = makeHistoryItems(count: 120)

        viewModel.onAllChange(Results(items: items, isSearchResult: false), (nil, nil))
        viewModel.loadNextPageIfNeeded(currentItemID: items[28].id)
        XCTAssertEqual(viewModel.visibleItems.count, 70)

        let filtered = Array(items.prefix(12))
        viewModel.onAllChange(Results(items: filtered, isSearchResult: true), (nil, nil))

        XCTAssertEqual(viewModel.visibleItems.count, 12)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), filtered.map(\.id))
    }

    func testSelectionOutsideVisibleWindowExpandsVisibleItems() {
        let viewModel = YippyViewModel()
        let items = makeHistoryItems(count: 120)

        viewModel.onAllChange(Results(items: items, isSearchResult: false), (nil, 55))

        XCTAssertEqual(viewModel.visibleItems.count, 70)
        XCTAssertEqual(viewModel.selectedItem?.id, items[55].id)
    }

    private func makeHistoryItem(text: String, category: HistoryItemCategory, createdAt: Date?) -> HistoryItem {
        let item = HistoryItem(
            unsavedData: [.string: text.data(using: .utf8)!],
            cache: HistoryCache(),
            originBundleId: "com.apple.TextEdit"
        )
        item.metadata = HistoryItemMetadata(
            category: category,
            codeSource: nil,
            createdAt: createdAt,
            originBundleId: "com.apple.TextEdit"
        )
        return item
    }

    private func makeHistoryItems(count: Int) -> [HistoryItem] {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        return (0..<count).map { index in
            makeHistoryItem(
                text: "Item \(index)",
                category: .text,
                createdAt: now.addingTimeInterval(TimeInterval(-index * 60))
            )
        }
    }
}
