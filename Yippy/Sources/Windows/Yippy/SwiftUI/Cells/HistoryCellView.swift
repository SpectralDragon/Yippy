//
//  HistoryCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryCellView: View {
    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    var body: some View {
        switch snapshot.contentKind {
        case .fileThumbnail:
            HistoryFileThumbnailCellView(snapshot: snapshot, proxy: proxy)
        case .fileIcon:
            HistoryFileIconCellView(snapshot: snapshot, proxy: proxy)
        case .text:
            HistoryTextCellView(snapshot: snapshot, proxy: proxy)
        case .image:
            HistoryImageCellView(snapshot: snapshot, proxy: proxy)
        case .color:
            HistoryColorCellView(snapshot: snapshot)
        case .webLink:
            HistoryWebLinkCellView(snapshot: snapshot, proxy: proxy)
        }
    }
}
