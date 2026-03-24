//
//  HistoryFileIconCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryFileIconCellView: View {
    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    @Environment(\.historyCellSettings) private var settings

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                if let image = snapshot.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.iconSize.width, height: Self.iconSize.height)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: Self.iconSize.width, height: Self.iconSize.height)
                }
                if let iconFileName = snapshot.displayPath {
                    Text(AttributedString(iconFileName))
                        .frame(width: width)
                        .padding(.all, 8)
                        .materialBlur(style: .contentBackground, opacity: 0.9)
                }
            }
            .frame(
                width: self.width,
                height: Self.getItemHeight(for: snapshot, availableWidth: width, proxy: proxy, settings: settings)
            )

            CategoryBadgeView(
                category: snapshot.category,
                codeSource: snapshot.codeSource
            )
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .accessibilityIdentifier(Accessibility.identifiers.yippyFileIconCellView)
    }

    private var width: CGFloat {
        return self.proxy.size.width - settings.padding.xTotal
    }

    private static let textContainerInset = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    private static let iconViewPadding = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    private static let iconSize = NSSize(width: 32, height: 32)

    private static func getItemHeight(for snapshot: HistoryRowSnapshot, availableWidth: CGFloat, proxy: GeometryProxy, settings: HistoryCellSettings) -> CGFloat {
        let cellWidth = floor(availableWidth)

        let textViewHeight = getFileNameTextViewHeight(withCellWidth: cellWidth, for: snapshot, settings: settings)
        let minCellHeight = iconSize.height + settings.contentViewInsets.yTotal + iconViewPadding.yTotal
        let height = max(textViewHeight + settings.contentViewInsets.yTotal, minCellHeight)

        return ceil(height)
    }

    private static func getFileNameTextViewHeight(withCellWidth cellWidth: CGFloat, for snapshot: HistoryRowSnapshot, settings: HistoryCellSettings) -> CGFloat {
        let width = cellWidth - settings.contentViewInsets.xTotal - iconSize.width - textContainerInset.xTotal - iconViewPadding.xTotal

        let attrStr = snapshot.displayPath
            ?? NSAttributedString(string: snapshot.title, attributes: HistoryItemText.itemStringAttributes)
        let maxTextContainerHeight = Constants.panel.maxCellHeight - settings.contentViewInsets.yTotal - textContainerInset.yTotal
        let estHeight = attrStr.calculateSize(withMaxWidth: width).height

        return min(estHeight, maxTextContainerHeight) + textContainerInset.yTotal
    }
}
