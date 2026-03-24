//
//  YippyView.swift
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

class SUIYippyViewController: NSHostingController<YippyView> {
    required init?(coder: NSCoder) {
        super.init(coder: coder, rootView: YippyView())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if #available(macOS 26, *) {
            self.view.window?.backgroundColor = .clear
        }
    }
}

struct YippyView: View {
    
    enum Focus {
        case searchbar
    }
    
    @Bindable var viewModel = YippyViewModel()
    @FocusState private var focusState: Focus?

    @AppStorage("theme") private var theme: AppearanceTheme = AppearanceTheme.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            contentView
                .yippyBackground()
        }
        .padding(.top, NSApplication.isMacOS26 ? 28 : 0)
        .onChange(of: viewModel.isSearchBarFocused) { _, newValue in
            if newValue == true {
                self.focusState = .searchbar
            } else {
                self.focusState = nil
            }
        }
        .colorScheme(theme == .system ? colorScheme : (theme == .light ? .light : .dark))
    }

    @ViewBuilder
    private var contentView: some View {
        if #available(macOS 26, *) {
            liquidDesignView
                .safeAreaPadding(.top, 24)
                .navigationTitle(Text("Yippy"))
        } else {
            oldDesignView
                .safeAreaPadding(.top, 48)
        }
    }

}

@available(macOS 26.0, *)
private extension YippyView {
    private var liquidDesignView: some View {
        VStack(spacing: NotificationCenterStyle.headerSpacing) {
            liquidDesignHeaderView
            YippyHistoryTableView(viewModel: viewModel)
                .onAppear(perform: viewModel.onAppear)
                .padding(.top, 2)
        }
        .padding(.horizontal, NotificationCenterStyle.panelHorizontalPadding)
        .padding(.bottom, NotificationCenterStyle.panelBottomPadding)
    }

    private var liquidDesignHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yippy")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    Text(viewModel.itemCountLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    showSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
            }

            liquidDesignSearchView

            CategoryFilterView(
                selectedCategory: $viewModel.selectedCategory,
                availableCategories: viewModel.getAvailableCategories()
            )
            .accessibilityIdentifier(Accessibility.identifiers.yippyCategoryFilter)
            .onChange(of: viewModel.selectedCategory) { _, newValue in
                viewModel.onCategorySelected(newValue)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .accessibilityIdentifier(Accessibility.identifiers.yippyHeader)
        .glassEffect(
            .clear.tint(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16)),
            in: RoundedRectangle(cornerRadius: NotificationCenterStyle.headerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotificationCenterStyle.headerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
        }
    }

    private var liquidDesignSearchView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(text: $viewModel.searchBarValue, prompt: Text("Search clipboard (⌘\\)")) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .focused($focusState, equals: .searchbar)
            .autocorrectionDisabled()
            .onChange(of: viewModel.searchBarValue) { _, _ in
                viewModel.runSearch()
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .accessibilityIdentifier(Accessibility.identifiers.yippySearchField)
        .glassEffect(
            .regular.tint(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.06)),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), lineWidth: 1)
        }
    }
}

private extension YippyView {
    private var oldDesignView: some View {
        VStack(spacing: 4) {
            ZStack {
                Text("Yippy")
                    .font(.title)

                HStack {
                    Spacer()

                    Text(viewModel.itemCountLabel)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)

            TextField(text: $viewModel.searchBarValue, prompt: Text("Search For Something (􀆔\\)")) {
                Image(systemName: "magnifyingglass")
            }
            .focused($focusState, equals: .searchbar)
            .autocorrectionDisabled()
            .border(.secondary)
            .onChange(of: viewModel.searchBarValue) { _, _ in
                viewModel.runSearch()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            CategoryFilterView(
                selectedCategory: $viewModel.selectedCategory,
                availableCategories: viewModel.getAvailableCategories()
            )
            .onChange(of: viewModel.selectedCategory) { _, newValue in
                viewModel.onCategorySelected(newValue)
            }
            .padding(.bottom, 8)

            YippyHistoryTableView(viewModel: viewModel)
                .onAppear(perform: viewModel.onAppear)
                .padding(.vertical, 8)
        }
    }
}

struct YippyHistoryTableView: View {
    
    @Bindable var viewModel: YippyViewModel
    @Environment(\.colorScheme) private var colorScheme
    @SwiftUI.State private var hoveredItemID: UUID?

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                Group {
                    if #available(macOS 26.0, *) {
                        notificationCenterHistory(proxy: proxy)
                    } else {
                        legacyHistory(proxy: proxy)
                    }
                }
                .accessibilityIdentifier(Accessibility.identifiers.yippyTableView)
                .onChange(of: viewModel.selectedItem) { oldValue, newValue in
                    if let value = newValue {
                        reader.scrollTo(value)
                    }
                }
                .onChange(of: viewModel.scrollToTopRequest) { _, _ in
                    guard let firstItem = viewModel.visibleItems.first else { return }

                    reader.scrollTo(
                        firstItem,
                        anchor: viewModel.panelPosition == .horizontal ? .leading : .top
                    )
                }
            }
        }
        .environment(\.historyCellSettings, HistoryCellSettings())
    }

    private func legacyHistory(proxy: GeometryProxy) -> some View {
        ScrollView(viewModel.panelPosition) {
            if viewModel.panelPosition == .horizontal {
                LazyHStack(spacing: 12) {
                    legacyContent(proxy: proxy)
                }
            } else {
                LazyVStack(spacing: 4) {
                    legacyContent(proxy: proxy)
                        .padding(.top, 8)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func legacyContent(proxy: GeometryProxy) -> some View {
        ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element) { (visibleIndex, item) in
            let snapshot = viewModel.snapshot(for: item)
            let index = viewModel.index(for: item) ?? visibleIndex

            HistoryCellView(snapshot: snapshot, proxy: proxy)
                .yippyRowBackground(colorScheme: colorScheme)
                .id(item)
                .overlay(alignment: .topLeading) {
                    if index < 10 {
                        VStack {
                            HStack {
                                Spacer()

                                (Text(Image(systemName: "command")) + Text("+ \(index)"))
                                    .font(.system(size: 10))
                                    .padding(.all, 4)
                                    .foregroundStyle(Color.white)
                                    .background(
                                        RoundedRectangle(
                                            cornerRadius: NSApplication.isMacOS26 ? 16 : 7,
                                            style: .continuous
                                        )
                                        .fill(Color.accentColor)
                                    )
                                    .padding(4)
                            }

                            Spacer()
                        }
                    }

                    if viewModel.selectedItem == item {
                        RoundedRectangle(
                            cornerRadius: NSApplication.isMacOS26 ? 16 : 7,
                            style: .continuous
                        )
                        .stroke(Color.accentColor, lineWidth: 6)
                    }
                }
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: NSApplication.isMacOS26 ? 16 : 7,
                        style: .continuous
                    )
                )
                .onAppear {
                    viewModel.loadNextPageIfNeeded(currentItemID: item.id)
                    viewModel.prepareRowIfNeeded(for: item.id)
                }
                .onTapGesture {
                    viewModel.onSelectItem(at: index)
                }
                .contextMenu(menuItems: {
                    Button {
                        viewModel.paste(at: index)
                    } label: {
                        Label("Copy", systemImage: "document.on.document")
                    }

                    Button(role: .destructive) {
                        viewModel.delete(at: index)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                })
                .draggable(item)
        }
    }

    @available(macOS 26.0, *)
    private func notificationCenterHistory(proxy: GeometryProxy) -> some View {
        ScrollView(viewModel.panelPosition, showsIndicators: false) {
            if viewModel.panelPosition == .horizontal {
                LazyHStack(spacing: NotificationCenterStyle.cardSpacing) {
                    ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element) { visibleIndex, item in
                        let index = viewModel.index(for: item) ?? visibleIndex
                        notificationRow(item: item, index: index, proxy: proxy)
                            .frame(width: horizontalCardWidth(for: proxy))
                    }
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            } else {
                LazyVStack(alignment: .leading, spacing: NotificationCenterStyle.sectionSpacing) {
                    ForEach(viewModel.timelineSections) { section in
                        VStack(alignment: .leading, spacing: NotificationCenterStyle.cardSpacing) {
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }

                            ForEach(section.items) { item in
                                if let index = viewModel.index(for: item) {
                                    notificationRow(item: item, index: index, proxy: proxy)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
    }

    @available(macOS 26.0, *)
    private func notificationRow(item: HistoryItem, index: Int, proxy: GeometryProxy) -> some View {
        let isSelected = viewModel.selectedItem == item
        let isHovered = hoveredItemID == item.id
        let snapshot = viewModel.snapshot(for: item)

        return YippyNotificationCell(
            snapshot: snapshot,
            index: index,
            isSelected: isSelected,
            isHovered: isHovered,
            maxWidth: viewModel.panelPosition == .horizontal ? horizontalCardWidth(for: proxy) : nil
        )
        .id(item)
        .contentShape(RoundedRectangle(cornerRadius: NotificationCenterStyle.cardRadius, style: .continuous))
        .onAppear {
            viewModel.loadNextPageIfNeeded(currentItemID: item.id)
            viewModel.prepareRowIfNeeded(for: item.id)
        }
        .onHover { isHovering in
            hoveredItemID = isHovering ? item.id : nil
        }
        .onTapGesture {
            viewModel.onSelectItem(at: index)
        }
        .contextMenu {
            Button {
                viewModel.paste(at: index)
            } label: {
                Label("Copy", systemImage: "document.on.document")
            }

            Button(role: .destructive) {
                viewModel.delete(at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .draggable(item)
    }

    @available(macOS 26.0, *)
    private func horizontalCardWidth(for proxy: GeometryProxy) -> CGFloat {
        min(max(proxy.size.width * 0.44, 300), 380)
    }
}

extension YippyView {
    func showSettings() {
        Controller.main.settingsWindowController.showWindow(nil)
    }
}


extension NSApplication {
    static var isMacOS26: Bool {
        if #available(macOS 26, *) {
            true
        } else {
            false
        }
    }
}

@available(macOS 26.0, *)
private enum NotificationCenterStyle {
    static let panelHorizontalPadding: CGFloat = 14
    static let panelBottomPadding: CGFloat = 14
    static let headerSpacing: CGFloat = 14
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 10
    static let headerRadius: CGFloat = 28
    static let cardRadius: CGFloat = 24
    static let previewRadius: CGFloat = 18
    static let panelShape = RoundedRectangle(cornerRadius: 36, style: .continuous)
}

@available(macOS 26.0, *)
private struct YippyNotificationCell: View {
    let snapshot: HistoryRowSnapshot
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let maxWidth: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let body = snapshot.subtitle {
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .accessibilityIdentifier(Accessibility.identifiers.yippyNotificationPrimaryText)
            }

            notificationPreview
            notificationFooter
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(cardBackground)
        .overlay(alignment: .topTrailing) {
            if index < 10 && (isSelected || isHovered) {
                shortcutBadge
                    .padding(10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: NotificationCenterStyle.cardRadius, style: .continuous)
                .stroke(selectionColor.opacity(isSelected ? 0.95 : 0.22), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08), radius: 12, y: 8)
        .accessibilityIdentifier(Accessibility.identifiers.yippyNotificationCell)
        .accessibilityLabel(snapshot.accessibilityIdentifier)
        .accessibilityValue(snapshot.subtitle ?? snapshot.title)
    }

    @ViewBuilder
    private var notificationPreview: some View {
        if let previewImage = snapshot.previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: NotificationCenterStyle.previewRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: NotificationCenterStyle.previewRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18), lineWidth: 1)
                }
        } else if let previewText = snapshot.previewText {
            Text(AttributedString(previewText))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(
                        cornerRadius: NotificationCenterStyle.previewRadius,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18))
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: NotificationCenterStyle.previewRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14), lineWidth: 1)
                }
        } else if snapshot.isLoading {
            RoundedRectangle(cornerRadius: NotificationCenterStyle.previewRadius, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18))
                .frame(maxWidth: .infinity)
                .frame(height: 96)
        }
    }

    @ViewBuilder
    private var notificationFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            if let relativeTime = snapshot.relativeTime {
                Text(relativeTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier(Accessibility.identifiers.yippyNotificationTimeLabel)
            }

            if !snapshot.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(snapshot.chips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24))
                                )
                        }
                    }
                }
                .scrollDisabled(true)
            }
        }
    }

    private var shortcutBadge: some View {
        (Text(Image(systemName: "command")) + Text("\(index)"))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(selectionColor)
            )
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: NotificationCenterStyle.cardRadius, style: .continuous)

        return ZStack {
            shape
                .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08))

            shape
                .glassEffect(
                    .regular.tint(Color.black.opacity(colorScheme == .dark ? 0.36 : 0.10)).interactive(),
                    in: shape
                )

            shape
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 1)
        }
    }

    private var selectionColor: Color {
        isSelected ? Color.accentColor : Color.white
    }
}

@available(macOS 26.0, *)
private extension HistoryRowSnapshot {
    var accessibilityIdentifier: String {
        switch contentKind {
        case .fileThumbnail:
            return Accessibility.identifiers.yippyFileThumbnailCellView
        case .fileIcon:
            return Accessibility.identifiers.yippyFileIconCellView
        case .text:
            return Accessibility.identifiers.yippyTextCellView
        case .image:
            return Accessibility.identifiers.yippyTiffCellView
        case .color:
            return Accessibility.identifiers.yippyColorCellView
        case .webLink:
            return Accessibility.identifiers.yippyWebLinkCellView
        }
    }
}

private extension View {
    @ViewBuilder
    func yippyBackground() -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(8)
                .background {
                    NotificationCenterPanelChrome()
                }
                .contentShape(NotificationCenterStyle.panelShape)
        } else {
            self
                .materialBlur(style: .sidebar)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    func yippyRowBackground(colorScheme: ColorScheme) -> some View {
        if #available(macOS 26, *) {
            self
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .glassEffect(
                    .regular.tint(colorScheme == .dark ? nil : .accentColor.opacity(0.2)).interactive(),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        } else {
            self
                .clipShape(
                    RoundedRectangle(cornerRadius: 7)
                )
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
        }
    }
}

@available(macOS 26.0, *)
private struct NotificationCenterPanelChrome: View {
    var body: some View {
        VisualEffectView(style: .hudWindow)
            .opacity(0.95)
            .clipShape(NotificationCenterStyle.panelShape)
    }
}
