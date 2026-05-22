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

    init(shelf: Shelf) {
        self.shelf = shelf
    }

    var sortedItems: [PlacedItem] {
        shelf.items.sorted { $0.slotIndex < $1.slotIndex }
    }

    func queueGoods(image: UIImage, imagePath: String, modelContext: ModelContext) {
        let slotIndex = nextAvailableSlotIndex()
        let backwardTilt = simd_quatf(angle: Float.pi / 12, axis: SIMD3<Float>(1, 0, 0))
        let transform = TransformSnapshot(position: slotPosition(for: slotIndex), rotation: backwardTilt)
        let item = PlacedItem(imagePath: imagePath, transform: transform, slotIndex: slotIndex, shelf: shelf)

        shelf.items.append(item)
        shelf.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, image: image)
        mode = .goodsEdit
        selectedTarget = ARShelfSelectionTarget.item(item.id)
        statusMessage = "グッズを棚へ配置しました。編集モードで位置を調整できます。"
    }

    func selectItem(id: UUID?) {
        selectedTarget = id.map { ARShelfSelectionTarget.item($0) }

        if id == nil {
            statusMessage = mode.selectionPrompt
        } else {
            statusMessage = "グッズを選択しました。選択中のグッズだけ移動、回転、拡大縮小できます。"
        }
    }

    func selectShelf() {
        selectedTarget = ARShelfSelectionTarget.shelf
        statusMessage = "棚を選択しました。選択中の棚だけ移動、回転、拡大縮小できます。"
    }

    func switchMode(_ newMode: ARInteractionMode) {
        mode = newMode

        switch newMode {
        case .placement:
            selectedTarget = nil
        case .shelfEdit:
            if selectedTarget != ARShelfSelectionTarget.shelf {
                selectedTarget = nil
            }
        case .goodsEdit:
            if selectedItemID == nil {
                selectedTarget = nil
            }
        }

        statusMessage = newMode.selectionPrompt
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
            "棚編集モードです。棚のみ選択できます。"
        case .goodsEdit:
            "グッズ編集モードです。グッズのみ選択できます。"
        }
    }
}

/// SwiftUIからRealityKit側へ渡す、追加待ちのグッズ情報です。
struct PendingGoods {
    var item: PlacedItem
    var image: UIImage
}
