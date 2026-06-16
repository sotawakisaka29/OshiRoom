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
    @State private var isShowingHelpTips = false
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
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                isShowingHelpTips = true
                            }
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }

                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                isInterfaceHidden = true
                            }
                            viewModel.statusMessage = "UIを非表示にしました。オブジェクト以外をタップすると再表示できます。"
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                    }
                    .buttonStyle(.plain)
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

            if isShowingHelpTips {
                ARShelfTipsOverlay {
                    withAnimation(.snappy(duration: 0.22)) {
                        isShowingHelpTips = false
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddGoods, onDismiss: {
            viewModel.discardEmptySpatialPlacementSelection(modelContext: modelContext)
        }) {
            AddGoodsView { image, imagePath in
                viewModel.queueGoods(image: image, imagePath: imagePath, modelContext: modelContext)
                isShowingAddGoods = false
            } onModelSelected: { model in
                viewModel.queueModel(model, modelContext: modelContext)
                isShowingAddGoods = false
            }
        }
        .sheet(isPresented: $isShowingGoodsShelfPicker) {
            GoodsShelfPickerView(shelves: viewModel.visiblePlacedShelves) { selection in
                switch selection {
                case .shelf(let shelf):
                    viewModel.selectShelfForGoodsInsertion(id: shelf.id)
                case .spatialPlacement:
                    viewModel.selectSpatialPlacementForGoodsInsertion(modelContext: modelContext)
                }
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
                            isShowingGoodsShelfPicker = true
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
                            symbolName: rotationButtonSymbolName,
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

    private var rotationButtonSymbolName: String {
        "rotate.3d"
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

struct ARShelfTipsOverlay: View {
    let onDismiss: () -> Void
    @State private var selectedPage = 0

    private let pages = ARShelfTipPage.allCases

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARの使い方")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Tips")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(AppColors.elevatedSurface, in: Circle())
                            .overlay(Circle().stroke(AppColors.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 14) {
                    TabView(selection: $selectedPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            ARShelfTipPageCard(page: page)
                                .tag(index)
                                .padding(.horizontal, 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 270)

                    HStack(spacing: 8) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                            Capsule()
                                .fill(index == selectedPage ? AppColors.textPrimary : AppColors.separator)
                                .frame(width: index == selectedPage ? 18 : 8, height: 8)
                                .animation(.snappy(duration: 0.22), value: selectedPage)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text("スワイプで次の項目へ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppColors.background)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppColors.separator, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 30, x: 0, y: 16)
            .padding(.horizontal, 20)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

private struct ARShelfTipPage: Identifiable, CaseIterable {
    let id = UUID()
    let title: String
    let symbolName: String
    let items: [String]

    static let allCases: [ARShelfTipPage] = [
        ARShelfTipPage(
            title: "操作パネル",
            symbolName: "slider.horizontal.3",
            items: [
                "「棚 / グッズ / 複数」で編集モードを切り替えます。",
                "「棚を追加」「グッズ追加」から、置きたいものを足せます。",
                "「高さ調整」「回転」「削除」で、選択中の対象をまとめて調整できます。"
            ]
        ),
        ARShelfTipPage(
            title: "撮影してグッズを追加",
            symbolName: "camera.fill",
            items: [
                "「グッズ追加」を押して、写真選択か「カメラで撮影」を選びます。",
                "撮影後は背景除去やプレビューを確認して、「追加する」でAR空間に入れます。",
                "保存済みの3Dモデルがある場合は、「3Dモデルを選択」からも追加できます。"
            ]
        ),
        ARShelfTipPage(
            title: "うまくいかないとき",
            symbolName: "hand.tap.fill",
            items: [
								"棚を読み込む際には画面が重くなることがあります",
                "棚やオブジェクトは、平面の上に置くとうまくいきやすいです。",
                "右上の「戻る」ボタンで、前の操作を取り消せます。"
            ]
        ),
        ARShelfTipPage(
            title: "楽しむ",
            symbolName: "sparkles",
            items: [
                "右上の非表示ボタンでUIを消すと、AR空間そのものに集中できます。",
                "UIを非表示にしたあとに画面を長押しすると、スクリーンショットの共有シートが開きます。",
                "端末を動かして角度を変えながら、AR空間を自由に楽しめます。"
            ]
        )
    ]
}

private struct ARShelfTipPageCard: View {
    let page: ARShelfTipPage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: page.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(page.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(page.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AppColors.textPrimary)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    let onSelected: (GoodsPlacementDestination) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelected(.spatialPlacement)
                    dismiss()
                } label: {
                    GoodsPlacementDestinationRow(
                        title: "グッズのみ",
                        subtitle: "棚を使わず、空間にそのまま配置します",
                        symbolName: "sparkles.rectangle.stack",
                        tint: Color(red: 0.30, green: 0.56, blue: 0.78)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                ForEach(shelves) { shelf in
                    Button {
                        onSelected(.shelf(shelf))
                        dismiss()
                    } label: {
                        GoodsPlacementDestinationRow(
                            title: shelf.selectionDisplayName,
                            subtitle: "\(shelf.items.count)個のグッズ",
                            symbolName: shelf.template.symbolName,
                            tint: shelf.template.tint
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.groupedBackground)
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

enum GoodsPlacementDestination {
    case spatialPlacement
    case shelf(Shelf)
}

private struct GoodsPlacementDestinationRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: symbolName)
                        .foregroundStyle(tint)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
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
