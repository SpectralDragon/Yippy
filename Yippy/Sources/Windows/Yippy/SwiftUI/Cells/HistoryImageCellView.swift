//
//  HistoryImageCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryImageCellView: View {
    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    @Environment(\.historyCellSettings) private var settings

    var body: some View {
        Group {
            if let image = snapshot.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray)
            }
        }
        .frame(width: width,
               height: Self.imageHeight(for: snapshot, width: width, proxy: proxy, settings: settings))
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            CategoryBadgeView(
                category: snapshot.category,
                codeSource: snapshot.codeSource
            )
            .padding(8)
        }
        .accessibilityIdentifier(Accessibility.identifiers.yippyTiffCellView)
    }
    
    // MARK: - Private
    
    private var width: CGFloat {
        return proxy.size.width - settings.padding.xTotal
    }
    
    private static func imageHeight(
        for snapshot: HistoryRowSnapshot,
        width: CGFloat,
        proxy: GeometryProxy,
        settings: HistoryCellSettings
    ) -> CGFloat {
        let imagePadding = NSEdgeInsetsZero

        guard let imageSize = snapshot.previewImageSize else {
            return min(140, proxy.frame(in: .global).height)
        }

        let imageWidth = width - imagePadding.xTotal - settings.contentViewInsets.xTotal
        let maxImageHeight = imageSize.height
        let imageHeight = min(imageSize.height * imageWidth / max(imageSize.width, 1), maxImageHeight)
        let maxHeight = proxy.frame(in: .global).height
        let height = min(imageHeight + imagePadding.yTotal + settings.contentViewInsets.xTotal, maxHeight)

        return ceil(height)
    }
}
