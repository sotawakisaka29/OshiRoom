import SwiftData
import SwiftUI

/// ARで棚を配置し、グッズ追加と編集を行う画面です。
struct ARShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ARShelfViewModel
    @State private var isShowingAddGoods = false
    @State private var isInterfaceHidden = false

    init(shelf: Shelf) {
        _viewModel = State(initialValue: ARShelfViewModel(shelf: shelf))
    }

    var body: some View {
        Group {
            if hasCameraUsageDescription {
                arPlacementContent
            } else {
                CameraUsageDescriptionMissingView()
            }
        }
        .navigationTitle(viewModel.shelf.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isInterfaceHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if isInterfaceHidden == false {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isInterfaceHidden = true
                        viewModel.statusMessage = "UIを非表示にしました。オブジェクト以外をタップすると再表示できます。"
                    } label: {
                        Image(systemName: "eye.slash")
                    }

                    Button {
                        viewModel.requestSave()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
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
    }

    private var editControls: some View {
        VStack(spacing: 12) {
            StatusCapsule(message: viewModel.statusMessage)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.switchMode(.shelfEdit)
                    } label: {
                        BottomMenuItem(
                            title: "棚編集",
                            symbolName: "shippingbox",
                            isActive: viewModel.mode == .shelfEdit
                        )
                    }

                    Button {
                        viewModel.switchMode(.goodsEdit)
                    } label: {
                        BottomMenuItem(
                            title: "グッズ編集",
                            symbolName: "photo",
                            isActive: viewModel.mode == .goodsEdit
                        )
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
                }

                HStack(spacing: 10) {
                    Button {
                        isShowingAddGoods = true
                    } label: {
                        BottomMenuItem(title: "グッズ追加", symbolName: "photo.badge.plus")
                    }

                    Button {
                        viewModel.requestDeleteSelected()
                    } label: {
                        BottomMenuItem(
                            title: "削除",
                            symbolName: "trash",
                            foregroundColor: viewModel.selectedItemID == nil ? AppColors.textMuted : Color(red: 0.74, green: 0.04, blue: 0.10)
                        )
                    }
                    .disabled(viewModel.selectedItemID == nil)
                    .opacity(viewModel.selectedItemID == nil ? 0.55 : 1)

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
        .foregroundStyle(isActive ? .white : foregroundColor)
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
    ARShelfView(shelf: Shelf(name: "ライブ記念棚", template: .glass))
        .modelContainer(PreviewModelContainer.make())
}
