//
//  HistoryWebLinkCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryWebLinkCellView: View {
    let snapshot: HistoryRowSnapshot
    let proxy: GeometryProxy

    var body: some View {
        HistoryTextCellView(snapshot: snapshot, proxy: proxy)
        .accessibilityIdentifier(Accessibility.identifiers.yippyWebLinkCellView)
    }
}
