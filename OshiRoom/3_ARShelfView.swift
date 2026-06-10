import SwiftData
import SwiftUI
import UIKit

/// ARで棚を配置し、グッズ追加と編集を行う画面です。
struct ARShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ARShelfViewModel
    @State private var isShowingAddGoods = false
    @State private var isShowingGoodsShelfPicker = false
    @State private var isShowingAddShelf = false
    @State private var isInterfaceHidden = false
    @State private var snapshotToShare: SharedSnapshot?
    let onReady: () -> Void

    init(room: Room, onReady: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: ARShelfViewModel(room: room))
        self.onReady = onReady
    }

    var body: some View {
        Group {
            if hasCameraUsageDescription {
                arPlacementContent
            } else {
                CameraUsageDescriptionMissingView()
                    .onAppear {
                        onReady()
                    }
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
        .statusBarHidden(isInterfaceHidden)
        .toolbar(.hidden, for: .tabBar)
    }

    private var arPlacementContent: some View {
        ZStack(alignment: .bottom) {
            ARShelfRealityView(
                viewModel: viewModel,
                modelContext: modelContext,
                isInterfaceHidden: isInterfaceHidden,
                onReady: onReady,
                onRequestShowInterface: {
                    isInterfaceHidden = false
                },
                onSnapshotSaved: { image in
                    snapshotToShare = SharedSnapshot(image: image)
                }
            )
                .ignoresSafeArea()

            if isInterfaceHidden == false {
                editControls
            }

            if viewModel.isRestoringRoomAnchor {
                RestoringRoomAnchorOverlay()
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
        .sheet(item: $snapshotToShare) { snapshot in
            ActivityView(activityItems: [snapshot.image]) {
                snapshotToShare = nil
            }
        }
    }

    private var editControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        _ = viewModel.undoLastEdit(modelContext: modelContext)
                    } label: {
                        EditorTabItem(
                            title: "戻す",
                            symbolName: "arrow.uturn.backward",
                            isActive: false
                        )
                    }
                    .disabled(viewModel.canUndo == false)
                    .opacity(viewModel.canUndo ? 1 : 0.5)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        viewModel.switchMode(.shelfEdit)
                    } label: {
                        EditorTabItem(
                            title: "棚",
                            symbolName: "shippingbox",
                            isActive: activeEditorMode == .shelfEdit
                        )
                    }

                    Button {
                        viewModel.switchMode(.goodsEdit)
                    } label: {
                        EditorTabItem(
                            title: "グッズ",
                            symbolName: "photo",
                            isActive: activeEditorMode == .goodsEdit
                        )
                    }

                    Button {
                        viewModel.toggleMultipleSelection()
                    } label: {
                        EditorTabItem(
                            title: "複数",
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

private struct SharedSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

struct RoomEntryLoadingOverlay: View {
    let roomName: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                loadingDoor

                Text("\(roomName)に入室中です")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.background)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppColors.textPrimary.opacity(0.22))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppColors.background.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var loadingDoor: some View {
        TimelineView(.periodic(from: .now, by: 0.14)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.14) % 2

            ZStack {
                doorImage(systemName: "door.left.hand.closed")
                    .opacity(phase == 0 ? 1 : 0)

                doorImage(systemName: "door.left.hand.open")
                    .opacity(phase == 0 ? 0 : 1)
            }
            .frame(width: 86, height: 86)
            .background(
                Circle()
                    .fill(AppColors.textPrimary.opacity(0.28))
            )
            .animation(.easeInOut(duration: 0.1), value: phase)
        }
    }

    private func doorImage(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(AppColors.background)
            .transition(
                .opacity.combined(with: .scale(scale: 0.88))
            )
    }

}

struct RestoringRoomAnchorOverlay: View {
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                loadingOrb

                Text("読み込み中です")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.background.opacity(0.96))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.background.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
            .padding(.top, 18)
            .padding(.horizontal, 20)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var loadingOrb: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.97 + (sin(time * 2.1) + 1) * 0.03

            ZStack {
                Circle()
                    .fill(AppColors.background.opacity(0.18))
                    .frame(width: 18, height: 18)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.background.opacity(0.96),
                                AppColors.background.opacity(0.68)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 8, height: 8)
            }
            .frame(width: 18, height: 18)
            .scaleEffect(pulse)
        }
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
                .font(.caption.weight(.semibold))
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
