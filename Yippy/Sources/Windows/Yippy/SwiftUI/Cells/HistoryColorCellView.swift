//
//  HistoryColorCellView.swift
//  Yippy
//
//  Created by v.prusakov on 2/13/24.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct HistoryColorCellView: View {
    let snapshot: HistoryRowSnapshot

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Group {
                if let color = snapshot.colorValue?.withAlphaComponent(1) {
                    Color(cgColor: color.cgColor)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.15))
                }
            }

            CategoryBadgeView(
                category: snapshot.category,
                codeSource: snapshot.codeSource
            )
        }
        .accessibilityIdentifier(Accessibility.identifiers.yippyColorCellView)
    }
}
