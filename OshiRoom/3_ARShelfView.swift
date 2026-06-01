import SwiftData
import SwiftUI

/// ARで棚を配置し、グッズ追加と編集を行う画面です。
struct ARShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ARShelfViewModel
    @State private var isShowingAddGoods = false
    @State private var isShowingGoodsShelfPicker = false
    @State private var isShowingAddShelf = false
    @State private var isInterfaceHidden = false

    init(room: Room) {
        _viewModel = State(initialValue: ARShelfViewModel(room: room))
    }

    var body: some View {
        Group {
            if hasCameraUsageDescription {
                arPlacementContent
            } else {
                CameraUsageDescriptionMissingView()
            }
        }
        .navigationTitle(viewModel.room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isInterfaceHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if isInterfaceHidden == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInterfaceHidden = true
                        viewModel.statusMessage = "UIを非表示にしました。オブジェクト以外をタップすると再表示できます。"
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var arPlacementContent: some View {
        ZStack(alignment: .bottom) {
            ARShelfRealityView(
                viewModel: viewModel,
                modelContext: modelContext,
                isInterfaceHidden: isInterfaceHidden,
                onRequestShowInterface: {
                    isInterfaceHidden = false
                }
            )
                .ignoresSafeArea()

            if isInterfaceHidden == false {
                editControls
            }
        }
        .sheet(isPresented: $isShowingAddGoods) {
            AddGoodsView { image, imagePath in
                viewModel.queueGoods(image: image, imagePath: imagePath, modelContext: modelContext)
                isShowingAddGoods = false
            } onModelSelected: { model in
                viewModel.queueModel(model, modelContext: modelContext)
                isShowingAddGoods = false
            }
        }
        .sheet(isPresented: $isShowingGoodsShelfPicker) {
            GoodsShelfPickerView(shelves: viewModel.placedShelves) { shelf in
                viewModel.selectShelfForGoodsInsertion(id: shelf.id)
                isShowingGoodsShelfPicker = false
                isShowingAddGoods = true
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingAddShelf) {
            ShelfTemplatePickerView { template in
                viewModel.addShelf(template: template, modelContext: modelContext)
                isShowingAddShelf = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var editControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.switchMode(.shelfEdit)
                    } label: {
                        EditorTabItem(
                            title: "棚編集",
                            symbolName: "shippingbox",
                            isActive: activeEditorMode == .shelfEdit
                        )
                    }

                    Button {
                        viewModel.switchMode(.goodsEdit)
                    } label: {
                        EditorTabItem(
                            title: "グッズ編集",
                            symbolName: "photo",
                            isActive: activeEditorMode == .goodsEdit
                        )
                    }

                    Button {
                        viewModel.toggleMultipleSelection()
                    } label: {
                        EditorTabItem(
                            title: "複数選択",
                            symbolName: "rectangle.3.group",
                            isActive: viewModel.isMultipleSelectionActive
                        )
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        if activeEditorMode == .shelfEdit {
                            isShowingAddShelf = true
                        } else {
                            if viewModel.placedShelves.isEmpty {
                                viewModel.statusMessage = "先にAR空間へ配置済みの棚を用意してください。"
                            } else {
                                isShowingGoodsShelfPicker = true
                            }
                        }
                    } label: {
                        BottomMenuItem(title: addButtonTitle, symbolName: addButtonSymbolName)
                    }

                    Button {
                        viewModel.toggleHeightAdjustment()
                    } label: {
                        BottomMenuItem(
                            title: "高さ調整",
                            symbolName: "arrow.up.and.down",
                            isActive: viewModel.isHeightAdjustmentActive
                        )
                    }

                    Button {
                        viewModel.toggleRotationAdjustment()
                    } label: {
                        BottomMenuItem(
                            title: "回転",
                            symbolName: "rotate.3d",
                            isActive: viewModel.isRotationAdjustmentActive
                        )
                    }

                    Button {
                        viewModel.requestDeleteSelected()
                    } label: {
                        BottomMenuItem(
                            title: "削除",
                            symbolName: "trash",
                            foregroundColor: canDeleteCurrentSelection ? Color(red: 0.74, green: 0.04, blue: 0.10) : AppColors.textMuted
                        )
                    }
                    .disabled(canDeleteCurrentSelection == false)
                    .opacity(canDeleteCurrentSelection ? 1 : 0.55)

                }
            }
            .padding(10)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppColors.separator, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
    }

    private var activeEditorMode: ARInteractionMode {
        viewModel.mode == .goodsEdit ? .goodsEdit : .shelfEdit
    }

    private var addButtonTitle: String {
        activeEditorMode == .shelfEdit ? "棚を追加" : "グッズ追加"
    }

    private var addButtonSymbolName: String {
        activeEditorMode == .shelfEdit ? "plus.square.on.square" : "photo.badge.plus"
    }

    private var canDeleteCurrentSelection: Bool {
        viewModel.canDeleteSelection
    }

    private var hasCameraUsageDescription: Bool {
        guard let message = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

/// AR画面下部に出す現在状態の表示です。
struct StatusCapsule: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.elevatedSurface, in: Capsule())
            .overlay(Capsule().stroke(AppColors.separator, lineWidth: 1))
    }
}

struct EditorTabItem: View {
    let title: String
    let symbolName: String
    var isActive = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(isActive ? AppColors.background : AppColors.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(isActive ? AppColors.textPrimary : AppColors.elevatedSurface, in: Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? AppColors.textPrimary : AppColors.separator, lineWidth: 1)
        )
    }
}

/// AR画面の固定メニュー用ボタンです。
struct BottomMenuItem: View {
    let title: String
    let symbolName: String
    var foregroundColor: Color = AppColors.textPrimary
    var isActive = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(isActive ? AppColors.background : foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(isActive ? AppColors.textPrimary : AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.separator, lineWidth: 1)
        )
    }
}

/// カメラ利用目的のInfo設定がないときに、クラッシュせず案内を出すViewです。
struct CameraUsageDescriptionMissingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 8) {
                Text("カメラ権限の設定が必要です")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("XcodeのTarget > InfoにPrivacy - Camera Usage Descriptionを追加すると、AR配置を開始できます。")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.groupedBackground)
    }
}

#Preview {
    ARShelfView(room: Room(name: "ライブ記念ルーム"))
        .modelContainer(PreviewModelContainer.make())
}

struct ShelfTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelected: (ShelfTemplate) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("棚を追加")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("置きたい棚の種類を選ぶと、次の床タップで追加できます。")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    ForEach(ShelfTemplate.allCases) { template in
                        ShelfTemplateRow(
                            template: template,
                            isSelected: false
                        ) {
                            onSelected(template)
                            dismiss()
                        }
                    }
                }
                .padding(22)
            }
            .background(AppColors.groupedBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GoodsShelfPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let shelves: [Shelf]
    let onSelected: (Shelf) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if shelves.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(AppColors.textSecondary)
                        Text("追加先の棚がありません")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("先に棚をAR空間へ配置してください。")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.groupedBackground)
                } else {
                    List {
                        ForEach(shelves) { shelf in
                            Button {
                                onSelected(shelf)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(shelf.template.tint.opacity(0.16))
                                        .frame(width: 58, height: 58)
                                        .overlay {
                                            Image(systemName: shelf.template.symbolName)
                                                .foregroundStyle(shelf.template.tint)
                                        }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(shelf.name)
                                            .font(.headline)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text("\(shelf.items.count)個のグッズ")
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(AppColors.textMuted)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.groupedBackground)
                }
            }
            .navigationTitle("追加先の棚")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

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

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .padding(14)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? AppColors.textPrimary.opacity(0.28) : AppColors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
