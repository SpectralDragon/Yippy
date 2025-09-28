import SwiftUI
import Observation

struct HistoryCategoryPickerView: View {

    @Bindable var viewModel: YippyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.categoryFilters) { filter in
                        HistoryFilterChip(title: filter.title, isSelected: filter == viewModel.selectedCategoryFilter)
                            .onTapGesture {
                                viewModel.selectCategory(filter)
                            }
                    }
                }
                .padding(.vertical, 2)
            }

            if viewModel.shouldShowCodeSourceFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.codeSourceFilters) { filter in
                            HistoryFilterChip(title: filter.displayName, isSelected: filter == viewModel.selectedCodeSourceFilter)
                                .onTapGesture {
                                    viewModel.selectCodeSource(filter)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct HistoryFilterChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
}

#Preview {
    HistoryCategoryPickerView(viewModel: YippyViewModel())
        .frame(width: 400)
}
