//
//  CategoryFilterView.swift
//  Yippy
//
//  Created by AI Assistant on 2024.
//  Copyright © 2024 MatthewDavidson. All rights reserved.
//

import SwiftUI

struct CategoryFilterView: View {
    @Binding var selectedCategory: HistoryItemCategory?
    let availableCategories: [HistoryItemCategory]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All categories button
                CategoryButton(
                    category: nil,
                    isSelected: selectedCategory == nil,
                    count: nil
                ) {
                    selectedCategory = nil
                }
                
                // Individual category buttons
                ForEach(availableCategories, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        count: nil // TODO: Add count calculation
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct CategoryButton: View {
    let category: HistoryItemCategory?
    let isSelected: Bool
    let count: Int?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if #available(macOS 26.0, *) {
                buttonLabel
                    .glassEffect(
                        .regular.tint(backgroundColor.opacity(isSelected ? 1 : 0.35)).interactive(),
                        in: Capsule(style: .continuous)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(borderColor.opacity(isSelected ? 0.45 : 0.18), lineWidth: 1)
                    }
            } else {
                buttonLabel
                    .background(backgroundColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var buttonLabel: some View {
        HStack(spacing: 4) {
            if let category = category {
                Image(systemName: category.iconName)
                    .font(.system(size: 12))
            } else {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
            }

            Text(displayName)
                .font(.system(size: 12, weight: .semibold))

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.3))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundColor(foregroundColor)
    }

    private var displayName: String {
        category?.displayName ?? "All"
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return category?.color.swiftUIColor.opacity(0.22) ?? Color.accentColor.opacity(0.22)
        } else {
            return Color.white.opacity(0.05)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return category?.color.swiftUIColor ?? Color.accentColor
        } else {
            return Color.primary.opacity(0.88)
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return category?.color.swiftUIColor ?? Color.accentColor
        } else {
            return Color.secondary.opacity(0.3)
        }
    }
}

#Preview {
    CategoryFilterView(
        selectedCategory: .constant(nil),
        availableCategories: [.text, .code, .url, .image, .file, .color]
    )
}
