import Foundation
import Observation
import SwiftData
import UIKit
import simd

/// AR空間で現在選択されている対象です。
enum ARShelfSelectionTarget: Equatable {
    case shelf(UUID)
    case item(UUID)
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
    var selectedTarget: ARShelfSelectionTarget?
    var shelfMoveMode: ShelfMoveMode = .horizontalPlane
    var goodsMoveMode: ShelfMoveMode = .horizontalPlane

    init(room: Room) {
        self.room = room
        self.statusMessage = room.shelves.contains(where: { $0.anchorTransformData != nil })
            ? "棚を選ぶか、「棚を追加」で新しい棚を置けます。"
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
        switch selectedTarget {
        case .shelf(let id):
            return id
        case .item:
            return selectedItem?.shelf?.id
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

    var selectedItemID: UUID? {
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
        selectedItemID != nil || selectedShelfID != nil
    }

    func addShelf(template: ShelfTemplate, modelContext: ModelContext) {
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
        switchMode(.shelfEdit)
        selectShelf(id: shelfID)
    }

    func queueGoods(image: UIImage, imagePath: String, modelContext: ModelContext) {
        guard let shelf = selectedShelf, shelf.anchorTransformData != nil else {
            statusMessage = "先に棚を選択してからグッズを追加してください。"
            return
        }

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
        selectedTarget = .item(item.id)
        statusMessage = "グッズを棚へ配置しました"
    }

    func selectShelfForGoodsInsertion(id: UUID) {
        guard let shelf = room.shelves.first(where: { $0.id == id }),
              shelf.anchorTransformData != nil else {
            statusMessage = "追加先の棚が見つかりませんでした。"
            return
        }

        mode = .goodsEdit
        selectedTarget = .shelf(id)
        statusMessage = "「\(shelf.name)」に追加します。写真か3Dモデルを選んでください。"
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

        let slotIndex = nextAvailableSlotIndex(in: shelf)
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
        room.updatedAt = .now
        modelContext.insert(item)
        pendingGoods = PendingGoods(item: item, content: .model3D(modelPath))
        mode = .goodsEdit
        selectedTarget = .item(item.id)
        statusMessage = "3Dモデルを棚へ配置しました"
    }

    func selectItem(id: UUID?) {
        selectedTarget = id.map { .item($0) }

        if id == nil {
            statusMessage = mode.selectionPrompt
        } else {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        }
    }

    func selectShelf(id: UUID?) {
        selectedTarget = id.map { .shelf($0) }

        if id == nil {
            statusMessage = mode.selectionPrompt
        } else {
            statusMessage = shelfMoveMode.shelfSelectedMessage
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
            if case .item = selectedTarget {
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
        if case .shelf = selectedTarget {
            statusMessage = shelfMoveMode.shelfSelectedMessage
        } else {
            statusMessage = shelfMoveMode.selectionPrompt
        }
    }

    private func toggleShelfRotationAdjustment() {
        shelfMoveMode = shelfMoveMode == .rotation ? .horizontalPlane : .rotation
        if case .shelf = selectedTarget {
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

    private func toggleGoodsRotationAdjustment() {
        goodsMoveMode = goodsMoveMode == .rotation ? .horizontalPlane : .rotation
        if selectedItemID != nil {
            statusMessage = goodsMoveMode.goodsSelectedMessage
        } else {
            statusMessage = goodsMoveMode.goodsSelectionPrompt
        }
    }

    func requestDeleteSelected() {
        guard canDeleteSelection else {
            statusMessage = mode == .shelfEdit
                ? "先に削除したい棚をタップして選択してください。"
                : "先に削除したいグッズをタップして選択してください。"
            return
        }

        deleteRequestToken += 1
    }

    func deleteSelected(modelContext: ModelContext) -> Bool {
        switch selectedTarget {
        case .item:
            return deleteSelectedItem(modelContext: modelContext)
        case .shelf:
            return deleteSelectedShelf(modelContext: modelContext)
        case nil:
            statusMessage = "削除する対象が見つかりませんでした。"
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

    func requestSave() {
        saveRequestToken += 1
    }

    func save(modelContext: ModelContext) -> Bool {
        room.updatedAt = .now
        selectedShelf?.updatedAt = .now

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
            "棚編集"
        case .goodsEdit:
            "グッズ編集"
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
