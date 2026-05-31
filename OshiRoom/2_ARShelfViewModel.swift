import Foundation
import Observation
import SwiftData
import UIKit
import simd

/// AR空間で現在選択されている対象です。
enum ARShelfSelectionTarget: Equatable {
    case shelf
    case item(UUID)
}

/// AR配置画面の状態を管理し、SwiftDataへ保存するViewModelです。
@Observable
final class ARShelfViewModel {
    var shelf: Shelf
    var mode: ARInteractionMode = .placement
    var statusMessage = "床を映して、置きたい場所をタップしてください。"
    var pendingGoods: PendingGoods?
    var isProcessing = false
    var saveRequestToken = 0
    var deleteRequestToken = 0
    var selectedTarget: ARShelfSelectionTarget?
    var shelfMoveMode: ShelfMoveMode = .horizontalPlane
    var goodsMoveMode: ShelfMoveMode = .horizontalPlane

    init(shelf: Shelf) {
        self.shelf = shelf
    }

    var sortedItems: [PlacedItem] {
        shelf.items.sorted { $0.slotIndex < $1.slotIndex }
    }

    func queueGoods(image: UIImage, imagePath: String, modelContext: ModelContext) {
        let slotIndex = nextAvailableSlotIndex()
        let backwardTilt = simd_quatf(angle: -Float.pi / 12, axis: SIMD3<Float>(1, 0, 0))
        let transform = TransformSnapshot(position: slotPosition(for: slotIndex), rotation: backwardTilt)
        let item = PlacedItem(
            imagePath: imagePath,
            displayName: "オブジェクト\(slotIndex + 1)",
            transform: transform,
            slotIndex: slotIndex,
            shelf: shelf
        )

        shelf.items.append(item)
        shelf.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, content: .image(image))
        mode = .goodsEdit
        selectedTarget = ARShelfSelectionTarget.item(item.id)
        statusMessage = "グッズを棚へ配置しました"
    }

    func queueModel(_ model: ScannedModel, modelContext: ModelContext) {
        guard let modelPath = model.modelPath else {
            statusMessage = "この3DモデルにはUSDZファイルがありません。"
            return
        }

        let slotIndex = nextAvailableSlotIndex()
        let transform = TransformSnapshot(
            position: modelSlotPosition(for: slotIndex),
            scale: SIMD3<Float>(repeating: 1)
        )
        let item = PlacedItem(
            imagePath: "",
            modelPath: modelPath,
            contentType: .model3D,
            displayName: model.name,
            transform: transform,
            slotIndex: slotIndex,
            shelf: shelf
        )

        shelf.items.append(item)
        shelf.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, content: .model3D(modelPath))
        mode = .goodsEdit
        selectedTarget = ARShelfSelectionTarget.item(item.id)
        statusMessage = "3Dモデルを棚へ配置しました"
    }

    func selectItem(id: UUID?) {
        selectedTarget = id.map { ARShelfSelectionTarget.item($0) }

        if id == nil {
            statusMessage = mode.selectionPrompt
        } else {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        }
    }

    func selectShelf() {
        selectedTarget = ARShelfSelectionTarget.shelf
        statusMessage = shelfMoveMode.shelfSelectedMessage
    }

    func switchMode(_ newMode: ARInteractionMode) {
        mode = newMode

        switch newMode {
        case .placement:
            selectedTarget = nil
            shelfMoveMode = .horizontalPlane
            goodsMoveMode = .horizontalPlane
        case .shelfEdit:
            shelfMoveMode = .horizontalPlane
            goodsMoveMode = .horizontalPlane
            if selectedTarget != ARShelfSelectionTarget.shelf {
                selectedTarget = nil
            }
        case .goodsEdit:
            shelfMoveMode = .horizontalPlane
            goodsMoveMode = .horizontalPlane
            if selectedItemID == nil {
                selectedTarget = nil
            }
        }

        statusMessage = newMode.selectionPrompt
    }

    var isHeightAdjustmentActive: Bool {
        (mode == .shelfEdit && shelfMoveMode == .height)
            || (mode == .goodsEdit && goodsMoveMode == .height)
    }

    func toggleHeightAdjustment() {
        switch mode {
        case .placement:
            switchMode(.shelfEdit)
            toggleShelfHeightAdjustment()
        case .shelfEdit:
            toggleShelfHeightAdjustment()
        case .goodsEdit:
            toggleGoodsHeightAdjustment()
        }
    }

    private func toggleShelfHeightAdjustment() {
        shelfMoveMode = shelfMoveMode == .height ? .horizontalPlane : .height
        if selectedTarget == ARShelfSelectionTarget.shelf {
            statusMessage = shelfMoveMode.shelfSelectedMessage
        } else {
            statusMessage = shelfMoveMode.selectionPrompt
        }
    }

    private func toggleGoodsHeightAdjustment() {
        goodsMoveMode = goodsMoveMode == .height ? .horizontalPlane : .height
        if selectedItemID != nil {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else {
            statusMessage = goodsMoveMode.goodsSelectionPrompt
        }
    }

    func requestDeleteSelected() {
        guard selectedItemID != nil else {
            statusMessage = "先に削除したいグッズをタップして選択してください。"
            return
        }

        deleteRequestToken += 1
    }

    func deleteSelected(modelContext: ModelContext) -> Bool {
        guard let selectedItemID,
              let item = shelf.items.first(where: { $0.id == selectedItemID }) else {
            statusMessage = "削除するグッズが見つかりませんでした。"
            return false
        }

        shelf.items.removeAll { $0.id == selectedItemID }
        modelContext.delete(item)
        selectedTarget = nil
        shelf.updatedAt = .now

        do {
            try modelContext.save()
            statusMessage = "グッズを削除しました。"
            return true
        } catch {
            statusMessage = "削除の保存に失敗しました。もう一度試してください。"
            return false
        }
    }

    func requestSave() {
        saveRequestToken += 1
    }

    func save(modelContext: ModelContext) -> Bool {
        shelf.updatedAt = .now

        do {
            try modelContext.save()
            statusMessage = "保存しました。"
            return true
        } catch {
            statusMessage = "保存できませんでした。少し待ってもう一度試してください。"
            return false
        }
    }

    func slotPosition(for index: Int) -> SIMD3<Float> {
        let column = index % 4
        let row = index / 4
        let x = -0.27 + Float(column) * 0.18
        let y = 0.08 + Float(row) * 0.15
        let z: Float = -0.0025
        return [x, y, z]
    }

    func modelSlotPosition(for index: Int) -> SIMD3<Float> {
        let basePosition = slotPosition(for: index)
        let row = index / 4
        let shelfSurfaceOffset: Float = 0.006
        let shelfSurfaceY = Float(row) * 0.15 + shelfSurfaceOffset
        return [basePosition.x, shelfSurfaceY, basePosition.z]
    }

    private func nextAvailableSlotIndex() -> Int {
        let usedSlots = Set(shelf.items.map(\.slotIndex))
        var index = 0

        while usedSlots.contains(index) {
            index += 1
        }

        return index
    }

    var selectedItemID: UUID? {
        guard case let .item(id) = selectedTarget else {
            return nil
        }

        return id
    }
}

/// AR内の操作モードです。
enum ARInteractionMode: String, CaseIterable, Identifiable {
    case placement
    case shelfEdit
    case goodsEdit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .placement:
            "配置"
        case .shelfEdit:
            "棚編集"
        case .goodsEdit:
            "グッズ編集"
        }
    }

    var selectionPrompt: String {
        switch self {
        case .placement:
            "床を映して、置きたい場所をタップしてください。"
        case .shelfEdit:
            "棚のみ選択できます。"
        case .goodsEdit:
            "グッズのみ選択できます。"
        }
    }
}

/// 棚編集中の移動方向です。
enum ShelfMoveMode {
    case horizontalPlane
    case height

    var selectionPrompt: String {
        switch self {
        case .horizontalPlane:
            "棚編集モードです。棚を選択すると左右・前後に移動できます。"
        case .height:
            "高さ調整モードです。棚を選択して縦にドラッグすると上下に移動できます。"
        }
    }

    var goodsSelectionPrompt: String {
        switch self {
        case .horizontalPlane:
            "グッズ編集モードです。グッズを選択すると左右・前後に移動できます。"
        case .height:
            "グッズ高さ調整モードです。グッズを選択して縦にドラッグすると上下に移動できます。"
        }
    }

    var shelfSelectedMessage: String {
        switch self {
        case .horizontalPlane:
            "棚を選択しました。ドラッグで左右・前後移動、ピンチや回転で調整できます。"
        case .height:
            "高さ調整中です。縦にドラッグすると棚を上下に移動できます。"
        }
    }

    var goodsSelectedMessage: String {
        switch self {
        case .horizontalPlane:
            "グッズを選択しました。ドラッグで左右・前後移動、ピンチや回転で調整できます。"
        case .height:
            "グッズ高さ調整中です。縦にドラッグすると選択中のグッズを上下に移動できます。"
        }
    }
}

/// SwiftUIからRealityKit側へ渡す、追加待ちのグッズ情報です。
struct PendingGoods {
    var item: PlacedItem
    var content: PendingGoodsContent
}

enum PendingGoodsContent {
    case image(UIImage)
    case model3D(String)
}
