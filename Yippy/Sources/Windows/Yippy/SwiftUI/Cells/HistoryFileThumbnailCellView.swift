//
//  HistoryFileThumbnailCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI
import EasySkeleton

struct HistoryFileThumbnailCellView: View {
    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    @Environment(\.historyCellSettings) private var settings

    private var width: CGFloat {
        return proxy.size.width - self.settings.padding.xTotal
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Group {
                if snapshot.isLoading && snapshot.previewImage == nil {
                    RoundedRectangle(cornerRadius: 7)
                        .frame(width: width, height: Self.imageSize.height)
                        .skeletonable()
                } else {
                    ZStack {
                        if let previewImage = snapshot.previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: Self.imageSize.height)
                        }
                        
                        VStack {

                            Spacer()

                            if let attributedPath = snapshot.displayPath {
                                Text(AttributedString(attributedPath))
                                    .frame(width: width)
                                    .padding(.all, 8)
                                    .materialBlur(style: .contentBackground, opacity: 0.9)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            CategoryBadgeView(
                                category: snapshot.category,
                                codeSource: snapshot.codeSource
                            )
                            .padding(.bottom, 8)
                            .padding(.trailing, 8)
                        }
                    }
                    .frame(
                        width: self.width,
                        height: Self.getItemHeight(for: snapshot, availableWidth: width, settings: settings, proxy: proxy)
                    )
                }
            }
        }
        .accessibilityIdentifier(Accessibility.identifiers.yippyFileThumbnailCellView)
    }

    private static let fileNamePadding = NSEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)
    private static let imageSize = NSSize(width: 300, height: 200)
    private static let imageTopPadding: CGFloat = 5

    private static func getItemHeight(
        for snapshot: HistoryRowSnapshot,
        availableWidth: CGFloat,
        settings: HistoryCellSettings,
        proxy: GeometryProxy
    ) -> CGFloat {
        let cellWidth = floor(availableWidth)
        let textContainerWidth = cellWidth - settings.contentViewInsets.xTotal - fileNamePadding.xTotal

        let str = snapshot.displayPath
            ?? NSAttributedString(string: snapshot.title, attributes: HistoryItemText.itemStringAttributes)

        let estHeight = str.calculateSize(withMaxWidth: textContainerWidth).height

        let height = estHeight
            + settings.contentViewInsets.yTotal
            + fileNamePadding.yTotal
            + imageSize.height
            + imageTopPadding

        return ceil(height)
    }
}
