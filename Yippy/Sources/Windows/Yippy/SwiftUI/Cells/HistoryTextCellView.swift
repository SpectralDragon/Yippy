//
//  HistoryTextCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryTextCellView: View {
    @Environment(\.historyCellSettings) private var settings

    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 0) {
                if let previewText = snapshot.previewText {
                    Text(AttributedString(previewText))
                        .multilineTextAlignment(.leading)
                } else {
                    Text(snapshot.title)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(settings.textInset)

            CategoryBadgeView(
                category: snapshot.category,
                codeSource: snapshot.codeSource
            )
            .padding(.bottom, 6)
            .padding(.trailing, 6)
        }
        .frame(
            width: width,
            height: Self.calculateCellHeight(
                snapshot: snapshot,
                availableWidth: width,
                settings: settings
            )
        )
        .accessibilityIdentifier(Accessibility.identifiers.yippyTextCellView)
    }
    
    // MARK: - Private
    
    private var width: CGFloat {
        return proxy.size.width - settings.padding.xTotal
    }
    
    private static func getTextContainerWidth(cellWidth: CGFloat, settings: HistoryCellSettings) -> CGFloat {
        return cellWidth - settings.textInset.xTotal - settings.contentViewInsets.xTotal
    }
    
    private static func getTextContainerMaxHeight(settings: HistoryCellSettings) -> CGFloat {
        return Constants.panel.maxCellHeight - settings.textInset.yTotal - settings.contentViewInsets.yTotal
    }
    
    private static func getCellHeight(estTextHeight: CGFloat, settings: HistoryCellSettings) -> CGFloat {
        // Get the max height of the text container
        let maxTextContainerHeight = getTextContainerMaxHeight(settings: settings)
        
        return min(estTextHeight, maxTextContainerHeight) + settings.textInset.yTotal + settings.contentViewInsets.yTotal
    }
    
    private static func calculateCellHeight(
        snapshot: HistoryRowSnapshot,
        availableWidth: CGFloat,
        settings: HistoryCellSettings
    ) -> CGFloat {
        let cellWidth = floor(availableWidth)
        let width = Self.getTextContainerWidth(cellWidth: cellWidth, settings: settings)

        let attrStr = snapshot.previewText
            ?? NSAttributedString(string: snapshot.title, attributes: HistoryItemText.itemStringAttributes)

        let estTextHeight = attrStr.calculateSize(withMaxWidth: width).height
        let categoryBadgeHeight: CGFloat = 20
        let height = Self.getCellHeight(estTextHeight: estTextHeight + categoryBadgeHeight, settings: settings)

        return ceil(height)
    }
}
