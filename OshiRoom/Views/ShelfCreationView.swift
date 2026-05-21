import SwiftData
import SwiftUI

/// 棚名とテンプレートを選び、新しい棚を作る画面です。
struct ShelfCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ShelfCreationViewModel()
    let onCreated: (Shelf) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新しい棚")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("まずは展示の雰囲気を決めます。あとからAR空間に配置できます。")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("棚名")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        TextField("例: ライブ記念グッズ棚", text: $viewModel.name)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppColors.separator, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("棚テンプレート")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)

                        ForEach(ShelfTemplate.allCases) { template in
                            ShelfTemplateRow(
                                template: template,
                                isSelected: viewModel.selectedTemplate == template
                            ) {
                                viewModel.selectedTemplate = template
                            }
                        }
                    }

                    if let message = viewModel.validationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 0.74, green: 0.04, blue: 0.10))
                    }
                }
                .padding(22)
            }
            .background(Color(red: 0.98, green: 0.98, blue: 0.97).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let shelf = viewModel.createShelf(in: modelContext) {
                            onCreated(shelf)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.canSave == false)
                }
            }
        }
    }
}

/// 棚テンプレートを選ぶための行です。
struct ShelfTemplateRow: View {
    let template: ShelfTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: template.symbolName)
                    .font(.title3)
                    .foregroundStyle(template.tint)
                    .frame(width: 46, height: 46)
                    .background(template.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.black : AppColors.textMuted)
            }
            .padding(14)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? Color.black.opacity(0.28) : AppColors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ShelfCreationView { _ in }
        .modelContainer(PreviewModelContainer.make())
}
