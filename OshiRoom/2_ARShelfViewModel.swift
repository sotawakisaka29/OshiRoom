import Foundation
import Observation
import SwiftData
import UIKit
import simd

/// AR空間で現在選択されている対象です。
enum ARShelfSelectionTarget: Equatable, Hashable {
    case shelf(UUID)
    case item(UUID)
    case allShelves
}

/// 直前の編集を元に戻すためのスナップショットです。
struct ARShelfUndoSnapshot {
    var room: ARShelfRoomSnapshot
    var mode: ARInteractionMode
    var selectedTarget: ARShelfSelectionTarget?
    var isMultipleSelectionActive: Bool
    var multiSelectionTargets: Set<ARShelfSelectionTarget>
    var shelfMoveMode: ShelfMoveMode
    var goodsMoveMode: ShelfMoveMode
}

struct ARShelfRoomSnapshot {
    var shelves: [ARShelfShelfSnapshot]
}

struct ARShelfShelfSnapshot {
    var id: UUID
    var name: String
    var templateRawValue: String
    var thumbnailData: Data?
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var anchorTransformData: Data?
    var items: [ARShelfItemSnapshot]
}

struct ARShelfItemSnapshot {
    var id: UUID
    var imagePath: String
    var imageData: Data?
    var modelPath: String?
    var contentTypeRawValue: String
    var displayName: String?
    var positionX: Float
    var positionY: Float
    var positionZ: Float
    var rotationX: Float
    var rotationY: Float
    var rotationZ: Float
    var rotationW: Float
    var scaleX: Float
    var scaleY: Float
    var scaleZ: Float
    var slotIndex: Int
    var createdAt: Date
}

/// AR配置画面の状態を管理し、SwiftDataへ保存するViewModelです。
@Observable
final class ARShelfViewModel {
    var room: Room
    var mode: ARInteractionMode = .placement
    var statusMessage: String
    var pendingGoods: PendingGoods?
    var pendingShelfID: UUID?
    var isProcessing = false
    var saveRequestToken = 0
    var deleteRequestToken = 0
    var sceneReloadRequestToken = 0
    var selectedTarget: ARShelfSelectionTarget?
    var isMultipleSelectionActive = false
    var multiSelectionTargets: Set<ARShelfSelectionTarget> = []
    var shelfMoveMode: ShelfMoveMode = .horizontalPlane
    var goodsMoveMode: ShelfMoveMode = .horizontalPlane
    private var undoSnapshots: [ARShelfUndoSnapshot] = []

    init(room: Room) {
        self.room = room
        mode = room.shelves.contains(where: { $0.anchorTransformData != nil }) ? .shelfEdit : .placement
        self.statusMessage = room.shelves.contains(where: { $0.anchorTransformData != nil })
            ? "棚をタップして選択できます。必要なら「棚を追加」でも新しい棚を置けます。"
            : "「棚を追加」を押して、最初の棚を置いてみましょう。"
    }

    var sortedShelves: [Shelf] {
        room.shelves.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var selectedShelfID: UUID? {
        if isMultipleSelectionActive {
            let shelfIDs = selectedShelfIDs
            return shelfIDs.count == 1 ? shelfIDs.first : nil
        }

        switch selectedTarget {
        case .shelf(let id):
            return id
        case .item:
            return selectedItem?.shelf?.id
        case .allShelves:
            return nil
        case nil:
            return nil
        }
    }

    var selectedShelf: Shelf? {
        guard let selectedShelfID else {
            return nil
        }
        return room.shelves.first { $0.id == selectedShelfID }
    }

    var selectedShelves: [Shelf] {
        if isMultipleSelectionActive {
            return selectedShelfIDs.compactMap { shelfID in
                room.shelves.first { $0.id == shelfID }
            }
        }

        if isAllShelvesSelectionActive {
            return placedShelves
        }

        guard let selectedShelf else {
            return []
        }

        return [selectedShelf]
    }

    var selectedItemID: UUID? {
        if isMultipleSelectionActive {
            let itemIDs = selectedItemIDs
            return itemIDs.count == 1 ? itemIDs.first : nil
        }

        guard case let .item(id) = selectedTarget else {
            return nil
        }
        return id
    }

    var selectedItem: PlacedItem? {
        guard let selectedItemID else {
            return nil
        }
        return room.shelves
            .flatMap(\.items)
            .first { $0.id == selectedItemID }
    }

    var pendingShelf: Shelf? {
        guard let pendingShelfID else {
            return nil
        }
        return room.shelves.first { $0.id == pendingShelfID }
    }

    var hasPlacedShelves: Bool {
        room.shelves.contains { $0.anchorTransformData != nil }
    }

    var placedShelves: [Shelf] {
        sortedShelves.filter { $0.anchorTransformData != nil }
    }

    var canDeleteSelection: Bool {
        hasActiveSelection
    }

    var canUndo: Bool {
        undoSnapshots.isEmpty == false
    }

    var isAllShelvesSelectionActive: Bool {
        selectedTarget == .allShelves
    }

    var hasActiveSelection: Bool {
        activeSelectionTargets.isEmpty == false
    }

    var activeSelectionTargets: [ARShelfSelectionTarget] {
        if isMultipleSelectionActive {
            return sortedSelectionTargets(multiSelectionTargets)
        }

        guard let selectedTarget else {
            return []
        }

        return [selectedTarget]
    }

    var selectedShelfIDs: [UUID] {
        activeSelectionTargets.compactMap { target in
            guard case let .shelf(id) = target else {
                return nil
            }

            return id
        }
    }

    var selectedItemIDs: [UUID] {
        activeSelectionTargets.compactMap { target in
            guard case let .item(id) = target else {
                return nil
            }

            return id
        }
    }

    var selectedItems: [PlacedItem] {
        selectedItemIDs.compactMap { itemID in
            room.shelves
                .flatMap(\.items)
                .first { $0.id == itemID }
        }
    }

    func addShelf(template: ShelfTemplate, modelContext: ModelContext) {
        let undoSnapshot = makeUndoSnapshot(includeImageData: false)
        let shelf = Shelf(
            name: nextShelfName(for: template),
            template: template,
            room: room
        )
        room.shelves.append(shelf)
        room.updatedAt = .now
        modelContext.insert(shelf)

        do {
            try modelContext.save()
            pushUndoSnapshot(undoSnapshot)
            pendingShelfID = shelf.id
            selectedTarget = nil
            mode = .placement
            statusMessage = "床をタップして「\(shelf.name)」を配置してください。"
        } catch {
            statusMessage = "棚を追加できませんでした。もう一度試してください。"
        }
    }

    func completePendingShelfPlacement(for shelfID: UUID) {
        pendingShelfID = nil
        isMultipleSelectionActive = false
        multiSelectionTargets.removeAll()
        switchMode(.shelfEdit)
        selectShelf(id: shelfID)
    }

    func toggleMultipleSelection() {
        if isMultipleSelectionActive {
            isMultipleSelectionActive = false
            clearSelection()
            statusMessage = mode.selectionPrompt
            return
        }

        if mode == .placement {
            switchMode(.shelfEdit)
        }

        isMultipleSelectionActive = true

        if let selectedTarget {
            switch selectedTarget {
            case .allShelves:
                multiSelectionTargets = Set(placedShelves.map { .shelf($0.id) })
            default:
                multiSelectionTargets = [selectedTarget]
            }
        }

        statusMessage = "複数選択を有効にしました。棚やオブジェクトをタップして追加できます。"
    }

    func queueGoods(image: UIImage, imagePath: String, modelContext: ModelContext) {
        guard let shelf = selectedShelf, shelf.anchorTransformData != nil else {
            statusMessage = "先に棚を選択してからグッズを追加してください。"
            return
        }

        let undoSnapshot = makeUndoSnapshot(includeImageData: false)
        let slotIndex = nextAvailableSlotIndex(in: shelf)
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
        room.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, content: .image(image))
        mode = .goodsEdit
        isMultipleSelectionActive = false
        multiSelectionTargets.removeAll()
        selectedTarget = .item(item.id)
        statusMessage = "グッズを棚へ配置しました"
        pushUndoSnapshot(undoSnapshot)
    }

    func selectShelfForGoodsInsertion(id: UUID) {
        guard let shelf = room.shelves.first(where: { $0.id == id }),
              shelf.anchorTransformData != nil else {
            statusMessage = "追加先の棚が見つかりませんでした。"
            return
        }

        mode = .goodsEdit
        isMultipleSelectionActive = false
        multiSelectionTargets.removeAll()
        selectedTarget = .shelf(id)
        statusMessage = "「\(shelf.name)」に追加します。写真か3Dモデルを選んでください。"
    }

    func toggleAllShelvesSelection() {
        toggleMultipleSelection()
    }

    func queueModel(_ model: ScannedModel, modelContext: ModelContext) {
        guard let shelf = selectedShelf, shelf.anchorTransformData != nil else {
            statusMessage = "先に棚を選択してから3Dモデルを追加してください。"
            return
        }

        guard let modelPath = model.modelPath else {
            statusMessage = "この3DモデルにはUSDZファイルがありません。"
            return
        }

        let undoSnapshot = makeUndoSnapshot(includeImageData: false)
        let slotIndex = nextAvailableSlotIndex(in: shelf)
        let transform = TransformSnapshot(
            position: modelSlotPosition(for: slotIndex),
            scale: SIMD3<Float>(repeating: 1)
        )
        let item = PlacedItem(
            imagePath: "",
            modelPath: modelPath,
            contentType: .model3D,
            displayName: snapshotDisplayName(for: model),
            transform: transform,
            slotIndex: slotIndex,
            shelf: shelf
        )

        shelf.items.append(item)
        shelf.updatedAt = .now
        room.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, content: .model3D(modelPath))
        mode = .goodsEdit
        isMultipleSelectionActive = false
        multiSelectionTargets.removeAll()
        selectedTarget = .item(item.id)
        statusMessage = "3Dモデルを棚へ配置しました"
        pushUndoSnapshot(undoSnapshot)
    }

    private func snapshotDisplayName(for model: ScannedModel) -> String? {
        let trimmedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    func selectItem(id: UUID?) {
        if isMultipleSelectionActive {
            if let id {
                let isSelected = toggleMultiSelectionTarget(.item(id))
                statusMessage = isSelected
                    ? goodsMoveMode.goodsSelectedMessage
                    : "選択を解除しました。"
            } else {
                clearSelection()
                statusMessage = mode.selectionPrompt
            }
        } else {
            selectedTarget = id.map { .item($0) }
            if id == nil {
                statusMessage = mode.selectionPrompt
            } else {
                statusMessage = goodsMoveMode.goodsSelectedMessage
            }
        }
    }

    func selectShelf(id: UUID?) {
        if isMultipleSelectionActive {
            if let id {
                let isSelected = toggleMultiSelectionTarget(.shelf(id))
                statusMessage = isSelected
                    ? shelfMoveMode.shelfSelectedMessage
                    : "選択を解除しました。"
            } else {
                clearSelection()
                statusMessage = mode.selectionPrompt
            }
        } else {
            selectedTarget = id.map { .shelf($0) }
            if id == nil {
                statusMessage = mode.selectionPrompt
            } else {
                statusMessage = shelfMoveMode.shelfSelectedMessage
            }
        }
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
            if isMultipleSelectionActive == false, case .item = selectedTarget {
                selectedTarget = nil
            }
        case .goodsEdit:
            shelfMoveMode = .horizontalPlane
            goodsMoveMode = .horizontalPlane
            if isMultipleSelectionActive == false, (selectedItemID == nil || isAllShelvesSelectionActive) {
                selectedTarget = nil
            }
        }

        statusMessage = newMode.selectionPrompt
    }

    var isHeightAdjustmentActive: Bool {
        (mode == .shelfEdit && shelfMoveMode == .height)
            || (mode == .goodsEdit && goodsMoveMode == .height)
    }

    var isRotationAdjustmentActive: Bool {
        (mode == .shelfEdit && shelfMoveMode == .rotation)
            || (mode == .goodsEdit && goodsMoveMode == .rotation)
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

    func toggleRotationAdjustment() {
        switch mode {
        case .placement:
            switchMode(.shelfEdit)
            toggleShelfRotationAdjustment()
        case .shelfEdit:
            toggleShelfRotationAdjustment()
        case .goodsEdit:
            toggleGoodsRotationAdjustment()
        }
    }

    private func toggleShelfHeightAdjustment() {
        shelfMoveMode = shelfMoveMode == .height ? .horizontalPlane : .height
        if isMultipleSelectionActive, selectedShelfIDs.isEmpty == false {
            statusMessage = shelfMoveMode == .height
                ? "複数の棚を選択しています。高さを調整できます。"
                : "複数の棚を選択しています。移動できます。"
        } else if selectedTarget == .allShelves {
            statusMessage = shelfMoveMode == .height
                ? "すべての棚を選択しています。高さを調整できます。"
                : "すべての棚を選択しています。移動できます。"
        } else if case .shelf = selectedTarget {
            statusMessage = shelfMoveMode.shelfSelectedMessage
        } else if isMultipleSelectionActive {
            statusMessage = "棚が選択されていません。棚を選択してから試してください。"
        } else {
            statusMessage = shelfMoveMode.selectionPrompt
        }
    }

    private func toggleShelfRotationAdjustment() {
        shelfMoveMode = shelfMoveMode == .rotation ? .horizontalPlane : .rotation
        if isMultipleSelectionActive, selectedShelfIDs.isEmpty == false {
            statusMessage = shelfMoveMode == .rotation
                ? "複数の棚を選択しています。回転を調整できます。"
                : "複数の棚を選択しています。移動できます。"
        } else if selectedTarget == .allShelves {
            statusMessage = shelfMoveMode == .rotation
                ? "すべての棚を選択しています。回転を調整できます。"
                : "すべての棚を選択しています。移動できます。"
        } else if case .shelf = selectedTarget {
            statusMessage = shelfMoveMode.shelfSelectedMessage
        } else if isMultipleSelectionActive {
            statusMessage = "棚が選択されていません。棚を選択してから試してください。"
        } else {
            statusMessage = shelfMoveMode.selectionPrompt
        }
    }

    private func toggleGoodsHeightAdjustment() {
        goodsMoveMode = goodsMoveMode == .height ? .horizontalPlane : .height
        if isMultipleSelectionActive, selectedItemIDs.isEmpty == false {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else if selectedItemID != nil {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else if isMultipleSelectionActive {
            statusMessage = "グッズが選択されていません。オブジェクトを選択してから試してください。"
        } else {
            statusMessage = goodsMoveMode.goodsSelectionPrompt
        }
    }

    private func toggleGoodsRotationAdjustment() {
        goodsMoveMode = goodsMoveMode == .rotation ? .horizontalPlane : .rotation
        if isMultipleSelectionActive, selectedItemIDs.isEmpty == false {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else if selectedItemID != nil {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else if isMultipleSelectionActive {
            statusMessage = "グッズが選択されていません。オブジェクトを選択してから試してください。"
        } else {
            statusMessage = goodsMoveMode.goodsSelectionPrompt
        }
    }

    func requestDeleteSelected() {
        guard canDeleteSelection else {
            statusMessage = mode == .shelfEdit
                ? "先に削除したい棚を選択してください。"
                : "先に削除したいグッズをタップして選択してください。"
            return
        }

        deleteRequestToken += 1
    }

    func deleteSelected(modelContext: ModelContext) -> Bool {
        if isMultipleSelectionActive || multiSelectionTargets.count > 1 {
            return deleteSelectedTargets(modelContext: modelContext)
        }

        switch selectedTarget {
        case .item:
            return deleteSelectedItem(modelContext: modelContext)
        case .shelf:
            return deleteSelectedShelf(modelContext: modelContext)
        case .allShelves:
            return deleteSelectedShelves(modelContext: modelContext)
        case nil:
            statusMessage = "削除する対象が見つかりませんでした。"
            return false
        }
    }

    private func deleteSelectedTargets(modelContext: ModelContext) -> Bool {
        let targets = activeSelectionTargets
        guard targets.isEmpty == false else {
            statusMessage = "削除する対象が見つかりませんでした。"
            return false
        }

        if targets.contains(.allShelves) {
            return deleteSelectedShelves(modelContext: modelContext)
        }

        let selectedShelfIDs = Set(targets.compactMap { target -> UUID? in
            guard case let .shelf(id) = target else { return nil }
            return id
        })

        let selectedItemIDs = Set(targets.compactMap { target -> UUID? in
            guard case let .item(id) = target else { return nil }
            return id
        })
        let didDeleteShelves = selectedShelfIDs.isEmpty == false

        var imagePathsToDelete: [String] = []

        for itemID in selectedItemIDs {
            guard let item = room.shelves.flatMap(\.items).first(where: { $0.id == itemID }),
                  let shelf = item.shelf,
                  selectedShelfIDs.contains(shelf.id) == false else {
                continue
            }

            shelf.items.removeAll { $0.id == item.id }
            modelContext.delete(item)
            if item.contentType == .image, item.imagePath.isEmpty == false {
                imagePathsToDelete.append(item.imagePath)
            }
            shelf.updatedAt = .now
        }

        for shelfID in selectedShelfIDs {
            guard let shelf = room.shelves.first(where: { $0.id == shelfID }) else {
                continue
            }

            imagePathsToDelete.append(contentsOf: shelf.items.filter { $0.contentType == .image && $0.imagePath.isEmpty == false }.map(\.imagePath))
            modelContext.delete(shelf)
        }

        room.shelves.removeAll { shelf in
            selectedShelfIDs.contains(shelf.id)
        }
        selectedTarget = nil
        multiSelectionTargets.removeAll()
        isMultipleSelectionActive = false
        room.updatedAt = .now
        if didDeleteShelves {
            mode = room.shelves.contains { $0.anchorTransformData != nil } ? .shelfEdit : .placement
        }

        do {
            try modelContext.save()
            imagePathsToDelete.forEach { ImageStore.delete(path: $0) }
            statusMessage = "選択した対象を削除しました。"
            return true
        } catch {
            statusMessage = "削除の保存に失敗しました。もう一度試してください。"
            return false
        }
    }

    private func deleteSelectedItem(modelContext: ModelContext) -> Bool {
        guard let selectedItem,
              let shelf = selectedItem.shelf else {
            statusMessage = "削除するグッズが見つかりませんでした。"
            return false
        }

        shelf.items.removeAll { $0.id == selectedItem.id }
        modelContext.delete(selectedItem)
        selectedTarget = nil
        shelf.updatedAt = .now
        room.updatedAt = .now

        do {
            try modelContext.save()
            statusMessage = "グッズを削除しました。"
            return true
        } catch {
            statusMessage = "削除の保存に失敗しました。もう一度試してください。"
            return false
        }
    }

    private func deleteSelectedShelf(modelContext: ModelContext) -> Bool {
        guard let shelf = selectedShelf else {
            statusMessage = "削除する棚が見つかりませんでした。"
            return false
        }

        let remainingPlacedShelves = room.shelves.contains { $0.id != shelf.id && $0.anchorTransformData != nil }
        room.shelves.removeAll { $0.id == shelf.id }
        modelContext.delete(shelf)
        selectedTarget = nil
        room.updatedAt = .now
        mode = remainingPlacedShelves ? .shelfEdit : .placement

        do {
            try modelContext.save()
            statusMessage = remainingPlacedShelves
                ? "棚を削除しました。"
                : "棚を削除しました。「棚を追加」で新しい棚を置けます。"
            return true
        } catch {
            statusMessage = "削除の保存に失敗しました。もう一度試してください。"
            return false
        }
    }

    private func deleteSelectedShelves(modelContext: ModelContext) -> Bool {
        let shelvesToDelete = placedShelves
        guard shelvesToDelete.isEmpty == false else {
            statusMessage = "削除する棚が見つかりませんでした。"
            return false
        }

        let imagePaths = shelvesToDelete
            .flatMap(\.items)
            .filter { $0.contentType == .image && $0.imagePath.isEmpty == false }
            .map(\.imagePath)

        for shelf in shelvesToDelete {
            modelContext.delete(shelf)
        }

        room.shelves.removeAll { shelf in
            shelf.anchorTransformData != nil
        }
        selectedTarget = nil
        room.updatedAt = .now
        mode = room.shelves.contains { $0.anchorTransformData != nil } ? .shelfEdit : .placement

        do {
            try modelContext.save()
            imagePaths.forEach { ImageStore.delete(path: $0) }
            statusMessage = room.shelves.contains { $0.anchorTransformData != nil }
                ? "棚を削除しました。"
                : "棚を削除しました。「棚を追加」で新しい棚を置けます。"
            return true
        } catch {
            statusMessage = "削除の保存に失敗しました。もう一度試してください。"
            return false
        }
    }

    func requestSave() {
        saveRequestToken += 1
    }

    func requestSceneReload() {
        sceneReloadRequestToken += 1
    }

    func undoLastEdit(modelContext: ModelContext) -> Bool {
        guard let snapshot = undoSnapshots.popLast() else {
            statusMessage = "元に戻せる編集がありません。"
            return false
        }

        restore(snapshot: snapshot, modelContext: modelContext)
        requestSceneReload()
        statusMessage = "直前の編集を元に戻しました。"
        return true
    }

    func captureUndoSnapshot(includeImageData: Bool) {
        undoSnapshots.append(makeUndoSnapshot(includeImageData: includeImageData))
        if undoSnapshots.count > 30 {
            undoSnapshots.removeFirst(undoSnapshots.count - 30)
        }
    }

    private func pushUndoSnapshot(_ snapshot: ARShelfUndoSnapshot) {
        undoSnapshots.append(snapshot)
        if undoSnapshots.count > 30 {
            undoSnapshots.removeFirst(undoSnapshots.count - 30)
        }
    }

    private func makeUndoSnapshot(includeImageData: Bool) -> ARShelfUndoSnapshot {
        ARShelfUndoSnapshot(
            room: ARShelfRoomSnapshot(shelves: room.shelves.map { shelf in
                ARShelfShelfSnapshot(
                    id: shelf.id,
                    name: shelf.name,
                    templateRawValue: shelf.templateRawValue,
                    thumbnailData: shelf.thumbnailData,
                    displayOrder: shelf.displayOrder,
                    createdAt: shelf.createdAt,
                    updatedAt: shelf.updatedAt,
                    anchorTransformData: shelf.anchorTransformData,
                    items: shelf.items.map { item in
                        ARShelfItemSnapshot(
                            id: item.id,
                            imagePath: item.imagePath,
                            imageData: includeImageData ? ImageStore.load(path: item.imagePath)?.pngData() : nil,
                            modelPath: item.modelPath,
                            contentTypeRawValue: item.contentTypeRawValue,
                            displayName: item.displayName,
                            positionX: item.positionX,
                            positionY: item.positionY,
                            positionZ: item.positionZ,
                            rotationX: item.rotationX,
                            rotationY: item.rotationY,
                            rotationZ: item.rotationZ,
                            rotationW: item.rotationW,
                            scaleX: item.scaleX,
                            scaleY: item.scaleY,
                            scaleZ: item.scaleZ,
                            slotIndex: item.slotIndex,
                            createdAt: item.createdAt
                        )
                    }
                )
            }),
            mode: mode,
            selectedTarget: selectedTarget,
            isMultipleSelectionActive: isMultipleSelectionActive,
            multiSelectionTargets: multiSelectionTargets,
            shelfMoveMode: shelfMoveMode,
            goodsMoveMode: goodsMoveMode
        )
    }

    private func restore(snapshot: ARShelfUndoSnapshot, modelContext: ModelContext) {
        for shelf in room.shelves {
            modelContext.delete(shelf)
        }
        room.shelves.removeAll()

        for shelfSnapshot in snapshot.room.shelves {
            let shelf = Shelf(
                id: shelfSnapshot.id,
                name: shelfSnapshot.name,
                template: ShelfTemplate(rawValue: shelfSnapshot.templateRawValue) ?? .wood,
                thumbnailData: shelfSnapshot.thumbnailData,
                displayOrder: shelfSnapshot.displayOrder,
                createdAt: shelfSnapshot.createdAt,
                updatedAt: shelfSnapshot.updatedAt,
                anchorTransformData: shelfSnapshot.anchorTransformData,
                room: room
            )

            for itemSnapshot in shelfSnapshot.items {
                if let imageData = itemSnapshot.imageData {
                    try? ImageStore.save(imageData, path: itemSnapshot.imagePath)
                }

                let item = PlacedItem(
                    id: itemSnapshot.id,
                    imagePath: itemSnapshot.imagePath,
                    modelPath: itemSnapshot.modelPath,
                    contentType: PlacedItemContentType(rawValue: itemSnapshot.contentTypeRawValue) ?? .image,
                    displayName: itemSnapshot.displayName,
                    transform: TransformSnapshot(
                        position: SIMD3<Float>(itemSnapshot.positionX, itemSnapshot.positionY, itemSnapshot.positionZ),
                        rotation: simd_quatf(vector: SIMD4<Float>(itemSnapshot.rotationX, itemSnapshot.rotationY, itemSnapshot.rotationZ, itemSnapshot.rotationW)),
                        scale: SIMD3<Float>(itemSnapshot.scaleX, itemSnapshot.scaleY, itemSnapshot.scaleZ)
                    ),
                    slotIndex: itemSnapshot.slotIndex,
                    createdAt: itemSnapshot.createdAt,
                    shelf: shelf
                )
                shelf.items.append(item)
                modelContext.insert(item)
            }

            room.shelves.append(shelf)
            modelContext.insert(shelf)
        }

        pendingGoods = nil
        pendingShelfID = nil
        isMultipleSelectionActive = snapshot.isMultipleSelectionActive
        multiSelectionTargets = snapshot.multiSelectionTargets
        selectedTarget = snapshot.selectedTarget
        mode = snapshot.mode
        shelfMoveMode = snapshot.shelfMoveMode
        goodsMoveMode = snapshot.goodsMoveMode
        room.updatedAt = .now

        try? modelContext.save()
    }

    func save(modelContext: ModelContext) -> Bool {
        room.updatedAt = .now
        selectedShelves.forEach { $0.updatedAt = .now }

        do {
            try modelContext.save()
            statusMessage = "保存しました。"
            return true
        } catch {
            statusMessage = "保存できませんでした。少し待ってもう一度試してください。"
            return false
        }
    }

    private func toggleMultiSelectionTarget(_ target: ARShelfSelectionTarget) -> Bool {
        var isSelected = true

        if multiSelectionTargets.contains(target) {
            multiSelectionTargets.remove(target)
            isSelected = false
        } else {
            multiSelectionTargets.insert(target)
        }

        selectedTarget = target
        return isSelected
    }

    private func clearSelection() {
        selectedTarget = nil
        multiSelectionTargets.removeAll()
    }

    private func sortedSelectionTargets(_ targets: Set<ARShelfSelectionTarget>) -> [ARShelfSelectionTarget] {
        targets.sorted { lhs, rhs in
            selectionSortKey(lhs) < selectionSortKey(rhs)
        }
    }

    private func selectionSortKey(_ target: ARShelfSelectionTarget) -> String {
        switch target {
        case .shelf(let id):
            return "0-\(id.uuidString)"
        case .item(let id):
            return "1-\(id.uuidString)"
        case .allShelves:
            return "2-all"
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

    private func nextAvailableSlotIndex(in shelf: Shelf) -> Int {
        let usedSlots = Set(shelf.items.map(\.slotIndex))
        var index = 0

        while usedSlots.contains(index) {
            index += 1
        }

        return index
    }

    private func nextShelfName(for template: ShelfTemplate) -> String {
        let existingNames = Set(room.shelves.map(\.name))
        let baseName = template.title

        if existingNames.contains(baseName) == false {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName)\(index)") {
            index += 1
        }

        return "\(baseName)\(index)"
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
            "棚"
        case .goodsEdit:
            "グッズ"
        }
    }

    var selectionPrompt: String {
        switch self {
        case .placement:
            "「棚を追加」から新しい棚を選び、床をタップして配置してください。"
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
    case rotation

    var selectionPrompt: String {
        switch self {
        case .horizontalPlane:
            "棚編集モードです。棚を選択すると左右・前後に移動できます。"
        case .height:
            "高さ調整モードです。棚を選択して縦にドラッグすると上下に移動できます。"
        case .rotation:
            "回転モードです。棚を選択してスワイプすると上下左右に回転できます。"
        }
    }

    var goodsSelectionPrompt: String {
        switch self {
        case .horizontalPlane:
            "グッズ編集モードです。グッズを選択すると左右・前後に移動できます。"
        case .height:
            "グッズ高さ調整モードです。グッズを選択して縦にドラッグすると上下に移動できます。"
        case .rotation:
            "回転モードです。グッズを選択してスワイプすると上下左右に回転できます。"
        }
    }

    var shelfSelectedMessage: String {
        switch self {
        case .horizontalPlane:
            "棚を選択しました。ドラッグで左右・前後移動、ピンチや回転で調整できます。"
        case .height:
            "高さ調整中です。縦にドラッグすると棚を上下に移動できます。"
        case .rotation:
            "回転調整中です。スワイプすると棚を上下左右に回転できます。"
        }
    }

    var goodsSelectedMessage: String {
        switch self {
        case .horizontalPlane:
            "グッズを選択しました。ドラッグで左右・前後移動、ピンチや回転で調整できます。"
        case .height:
            "グッズ高さ調整中です。縦にドラッグすると選択中のグッズを上下に移動できます。"
        case .rotation:
            "回転調整中です。スワイプすると選択中のグッズを上下左右に回転できます。"
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
