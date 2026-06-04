import ARKit
import CryptoKit
import Photos
import RealityKit
import SwiftData
import SwiftUI
import UIKit

/// SwiftUI画面の中でRealityKitのARViewを表示します。
struct ARShelfRealityView: UIViewRepresentable {
    let viewModel: ARShelfViewModel
    let modelContext: ModelContext
    let isInterfaceHidden: Bool
    let onReady: () -> Void
    let onRequestShowInterface: () -> Void
    let onSnapshotSaved: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            isInterfaceHidden: isInterfaceHidden,
            onReady: onReady,
            onRequestShowInterface: onRequestShowInterface,
            onSnapshotSaved: onSnapshotSaved
        )
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeARView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.modelContext = modelContext
        context.coordinator.isInterfaceHidden = isInterfaceHidden
        context.coordinator.onReady = onReady
        context.coordinator.onRequestShowInterface = onRequestShowInterface
        context.coordinator.onSnapshotSaved = onSnapshotSaved
        context.coordinator.updateMode(viewModel.mode)
        context.coordinator.reloadSceneIfNeeded(in: uiView)
        context.coordinator.syncShelvesIfNeeded(in: uiView)
        context.coordinator.consumePendingGoodsIfNeeded()
        context.coordinator.deleteIfNeeded(modelContext: modelContext)
        context.coordinator.saveIfNeeded(modelContext: modelContext)
        context.coordinator.notifyReadyIfNeeded()
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.persistBeforeDismiss()
    }

    final class Coordinator: NSObject {
        var viewModel: ARShelfViewModel
        var modelContext: ModelContext?
        var isInterfaceHidden: Bool
        var onReady: () -> Void
        var onRequestShowInterface: () -> Void
        var onSnapshotSaved: (UIImage) -> Void
        private weak var arView: ARView?
        private var anchorEntities: [UUID: AnchorEntity] = [:]
        private var shelfEntities: [UUID: ModelEntity] = [:]
        private var itemEntities: [UUID: ModelEntity] = [:]
        private var itemCollisionSizes: [UUID: SIMD3<Float>] = [:]
        private var itemCollisionCenters: [UUID: SIMD3<Float>] = [:]
        private var shelfGestureRecognizers: [UUID: [EntityGestureRecognizer]] = [:]
        private var itemGestureRecognizers: [UUID: [EntityGestureRecognizer]] = [:]
        private var shelfGroupPanGesture: UIPanGestureRecognizer?
        private var goodsGroupPanGesture: UIPanGestureRecognizer?
        private var heightPanGesture: UIPanGestureRecognizer?
        private var rotationPanGesture: UIPanGestureRecognizer?
        private var goodsPinchGesture: UIPinchGestureRecognizer?
        private var shelfGroupPanStartPositions: [UUID: SIMD3<Float>] = [:]
        private var goodsGroupPanStartPositions: [UUID: SIMD3<Float>] = [:]
        private var shelfGroupHeightStartPositions: [UUID: SIMD3<Float>] = [:]
        private var goodsGroupHeightStartPositions: [UUID: SIMD3<Float>] = [:]
        private var shelfGroupRotationStartOrientations: [UUID: simd_quatf] = [:]
        private var goodsGroupRotationStartOrientations: [UUID: simd_quatf] = [:]
        private var goodsGroupScaleStartScales: [UUID: SIMD3<Float>] = [:]
        private var heightPanStartY: Float = 0
        private var rotationPanStartOrientation: simd_quatf?
        private var goodsPinchStartScale: SIMD3<Float>?
        private var selectionOutlines: [Entity] = []
        private var outlinedTarget: ARShelfSelectionTarget?
        private var outlinedSelectionTargets: [ARShelfSelectionTarget] = []
        private var handledPendingGoodsID: UUID?
        private var handledSaveRequestToken = 0
        private var handledDeleteRequestToken = 0
        private var handledSceneReloadRequestToken = 0
        private var didNotifyReady = false
        private var activeItemGestureCount = 0
        private var isCapturingWorldMap = false

        init(
            viewModel: ARShelfViewModel,
            isInterfaceHidden: Bool,
            onReady: @escaping () -> Void,
            onRequestShowInterface: @escaping () -> Void,
            onSnapshotSaved: @escaping (UIImage) -> Void
        ) {
            self.viewModel = viewModel
            self.isInterfaceHidden = isInterfaceHidden
            self.onReady = onReady
            self.onRequestShowInterface = onRequestShowInterface
            self.onSnapshotSaved = onSnapshotSaved
        }

        func makeARView() -> ARView {
            let arView = ARView(frame: .zero)
            self.arView = arView
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.automaticallyConfigureSession = false

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            if let worldMap = WorldMapCoder.decode(viewModel.room.worldMapData) {
                configuration.initialWorldMap = worldMap
            }
            arView.session.run(configuration)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapGesture)

            let saveLongPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSaveLongPress(_:)))
            saveLongPressGesture.minimumPressDuration = 0.55
            saveLongPressGesture.allowableMovement = 12
            arView.addGestureRecognizer(saveLongPressGesture)

            let heightPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleHeightPan(_:)))
            heightPanGesture.maximumNumberOfTouches = 1
            heightPanGesture.isEnabled = false
            arView.addGestureRecognizer(heightPanGesture)
            self.heightPanGesture = heightPanGesture

            let shelfGroupPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleShelfGroupPan(_:)))
            shelfGroupPanGesture.maximumNumberOfTouches = 1
            shelfGroupPanGesture.isEnabled = false
            arView.addGestureRecognizer(shelfGroupPanGesture)
            self.shelfGroupPanGesture = shelfGroupPanGesture

            let goodsGroupPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleGoodsGroupPan(_:)))
            goodsGroupPanGesture.maximumNumberOfTouches = 1
            goodsGroupPanGesture.isEnabled = false
            arView.addGestureRecognizer(goodsGroupPanGesture)
            self.goodsGroupPanGesture = goodsGroupPanGesture

            let rotationPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRotationPan(_:)))
            rotationPanGesture.maximumNumberOfTouches = 1
            rotationPanGesture.isEnabled = false
            arView.addGestureRecognizer(rotationPanGesture)
            self.rotationPanGesture = rotationPanGesture

            let goodsPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleGoodsPinch(_:)))
            goodsPinchGesture.isEnabled = false
            arView.addGestureRecognizer(goodsPinchGesture)
            self.goodsPinchGesture = goodsPinchGesture
            return arView
        }

        func updateMode(_ mode: ARInteractionMode) {
            updateCollisionAvailability()
            updateGestureAvailability()
            updateSelectionOutline()
        }

        func syncShelvesIfNeeded(in arView: ARView) {
            for shelf in viewModel.sortedShelves {
                guard shelfEntities[shelf.id] == nil,
                      let matrix = MatrixCoder.decode(shelf.anchorTransformData) else {
                    continue
                }

                placeShelf(shelf, with: matrix, in: arView)
                restoreSavedItems(for: shelf)
            }
        }

        func saveIfNeeded(modelContext: ModelContext) {
            guard handledSaveRequestToken != viewModel.saveRequestToken else {
                return
            }

            handledSaveRequestToken = viewModel.saveRequestToken
            syncTransformsToModel()
            syncShelfTransformsToModel()
            _ = viewModel.save(modelContext: modelContext)
            captureWorldMapIfPossible(modelContext: modelContext)
        }

        func reloadSceneIfNeeded(in arView: ARView) {
            guard handledSceneReloadRequestToken != viewModel.sceneReloadRequestToken else {
                return
            }

            handledSceneReloadRequestToken = viewModel.sceneReloadRequestToken
            didNotifyReady = false
            clearSceneContent()
        }

        func persistBeforeDismiss() {
            guard let modelContext else {
                return
            }

            syncTransformsToModel()
            syncShelfTransformsToModel()
            _ = viewModel.save(modelContext: modelContext)
            captureWorldMapIfPossible(modelContext: modelContext)
        }

        func deleteIfNeeded(modelContext: ModelContext) {
            guard handledDeleteRequestToken != viewModel.deleteRequestToken else {
                return
            }

            handledDeleteRequestToken = viewModel.deleteRequestToken
            let targetsToDelete = viewModel.activeSelectionTargets
            if targetsToDelete.isEmpty == false {
                viewModel.captureUndoSnapshot(includeImageData: true)
                deleteSelectedEntities(for: targetsToDelete)
                clearSelectionOutline()
                syncTransformsToModel()
                syncShelfTransformsToModel()
                _ = viewModel.deleteSelected(modelContext: modelContext)
                updateCollisionAvailability()
                updateGestureAvailability()
                return
            }

            viewModel.statusMessage = viewModel.mode == .shelfEdit
                ? "先に削除したい棚をタップして選択してください。"
                : "先に削除したいグッズをタップして選択してください。"
        }

        private func deleteSelectedItemEntity(itemID: UUID) {
            itemEntities[itemID]?.removeFromParent()
            itemEntities[itemID] = nil
            itemCollisionSizes[itemID] = nil
            itemCollisionCenters[itemID] = nil
            itemGestureRecognizers[itemID]?.forEach { $0.isEnabled = false }
            itemGestureRecognizers[itemID] = nil
            activeItemGestureCount = 0
        }

        private func deleteSelectedShelfEntity(_ shelf: Shelf) {
            let imagePaths = shelf.items
                .filter { $0.contentType == .image && $0.imagePath.isEmpty == false }
                .map(\.imagePath)

            for item in shelf.items {
                deleteSelectedItemEntity(itemID: item.id)
            }

            shelfGestureRecognizers[shelf.id]?.forEach { $0.isEnabled = false }
            shelfGestureRecognizers[shelf.id] = nil
            shelfEntities[shelf.id]?.removeFromParent()
            shelfEntities[shelf.id] = nil
            anchorEntities[shelf.id]?.removeFromParent()
            anchorEntities[shelf.id] = nil
            imagePaths.forEach { ImageStore.delete(path: $0) }
        }

        private func deleteSelectedShelvesEntities() {
            for shelf in viewModel.placedShelves {
                deleteSelectedShelfEntity(shelf)
            }
        }

        private func deleteSelectedEntities(for targets: [ARShelfSelectionTarget]) {
            if targets.contains(.allShelves) {
                deleteSelectedShelvesEntities()
                return
            }

            for target in targets {
                switch target {
                case .item(let itemID):
                    deleteSelectedItemEntity(itemID: itemID)
                case .shelf(let shelfID):
                    guard let shelf = viewModel.room.shelves.first(where: { $0.id == shelfID }) else {
                        continue
                    }

                    deleteSelectedShelfEntity(shelf)
                case .allShelves:
                    continue
                }
            }
        }

        private func captureWorldMapIfPossible(modelContext: ModelContext) {
            guard let arView, isCapturingWorldMap == false else {
                return
            }

            isCapturingWorldMap = true
            arView.session.getCurrentWorldMap { [weak self] worldMap, error in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    self.isCapturingWorldMap = false
                    guard let worldMap else {
                        if let error {
                            self.viewModel.statusMessage = "ARの保存用マップを取得できませんでした: \(error.localizedDescription)"
                        }
                        return
                    }

                    self.viewModel.room.worldMapData = WorldMapCoder.encode(worldMap)
                    self.viewModel.room.updatedAt = .now

                    do {
                        try modelContext.save()
                    } catch {
                        self.viewModel.statusMessage = "ARの保存用マップを保存できませんでした。"
                    }
                }
            }
        }

        func consumePendingGoodsIfNeeded() {
            guard let pendingGoods = viewModel.pendingGoods else {
                return
            }

            guard handledPendingGoodsID != pendingGoods.item.id else {
                return
            }

            guard let shelfID = pendingGoods.item.shelf?.id,
                  let shelfEntity = shelfEntities[shelfID] else {
                viewModel.statusMessage = "先にグッズを置きたい棚を選択してください。"
                return
            }

            handledPendingGoodsID = pendingGoods.item.id
            switch pendingGoods.content {
            case .image(let image):
                addImageItemEntity(for: pendingGoods.item, image: image, to: shelfEntity, installGestures: true)
            case .model3D(let modelPath):
                addModelItemEntity(for: pendingGoods.item, modelPath: modelPath, to: shelfEntity, installGestures: true)
            }
            viewModel.pendingGoods = nil
            updateGestureAvailability()
            updateSelectionOutline()
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else {
                return
            }

            if isInterfaceHidden {
                onRequestShowInterface()
                return
            }

            let point = gesture.location(in: arView)
            if let pendingShelf = viewModel.pendingShelf {
                guard let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else {
                    viewModel.statusMessage = "床がまだ見つかっていません。ゆっくり部屋を映してください。"
                    return
                }

                viewModel.captureUndoSnapshot(includeImageData: false)
                placeShelf(pendingShelf, with: result.worldTransform, in: arView)
                pendingShelf.anchorTransformData = MatrixCoder.encode(result.worldTransform)
                pendingShelf.updatedAt = .now
                viewModel.room.updatedAt = .now
                viewModel.completePendingShelfPlacement(for: pendingShelf.id)
                updateCollisionAvailability()
                updateGestureAvailability()
                updateSelectionOutline()
                return
            }

            if shelfEntities.isEmpty == false {
                selectObject(at: point, in: arView)
            }
        }

        @objc private func handleSaveLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  isInterfaceHidden,
                  let arView else {
                return
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            viewModel.statusMessage = "スクリーンショットを保存しています..."

            arView.snapshot(saveToHDR: false) { [weak self] image in
                guard let self else {
                    return
                }

                guard let image else {
                    DispatchQueue.main.async {
                        self.viewModel.statusMessage = "スクリーンショットを取得できませんでした。"
                    }
                    return
                }

                self.saveSnapshotToPhotos(image)
            }
        }

        private func saveSnapshotToPhotos(_ image: UIImage) {
            let saveImage = image.normalizedForRendering()
            let performSave = { [weak self] in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: saveImage)
                }) { success, error in
                    DispatchQueue.main.async {
                        guard let self else {
                            return
                        }

                        if success {
                            self.viewModel.statusMessage = "スクリーンショットを写真に保存しました。"
                            self.onSnapshotSaved(saveImage)
                        } else if let error {
                            self.viewModel.statusMessage = "スクリーンショットを保存できませんでした: \(error.localizedDescription)"
                        } else {
                            self.viewModel.statusMessage = "スクリーンショットを保存できませんでした。"
                        }
                    }
                }
            }

            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                performSave()
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    switch status {
                    case .authorized, .limited:
                        performSave()
                    default:
                        DispatchQueue.main.async {
                            self.viewModel.statusMessage = "写真への保存権限がありません。"
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    self.viewModel.statusMessage = "写真への保存権限がありません。"
                }
            }
        }

        @objc private func handleHeightPan(_ gesture: UIPanGestureRecognizer) {
            if viewModel.isMultipleSelectionActive {
                if viewModel.mode == .shelfEdit, viewModel.selectedShelfIDs.isEmpty == false {
                    handleShelfGroupHeightPan(gesture)
                    return
                }

                if viewModel.mode == .goodsEdit, viewModel.selectedItemIDs.isEmpty == false {
                    handleGoodsGroupHeightPan(gesture)
                    return
                }
            }

            if viewModel.isAllShelvesSelectionActive {
                handleShelfGroupHeightPan(gesture)
                return
            }

            guard let targetEntity = heightAdjustmentTargetEntity() else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                heightPanStartY = targetEntity.position.y
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let nextY = heightPanStartY - Float(translation.y) * 0.0012
                targetEntity.position.y = min(max(nextY, -0.3), 1.5)
            case .ended, .cancelled, .failed:
                syncHeightAdjustedTargetToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        @objc private func handleRotationPan(_ gesture: UIPanGestureRecognizer) {
            if viewModel.isMultipleSelectionActive {
                if viewModel.mode == .shelfEdit, viewModel.selectedShelfIDs.isEmpty == false {
                    handleShelfGroupRotationPan(gesture)
                    return
                }

                if viewModel.mode == .goodsEdit, viewModel.selectedItemIDs.isEmpty == false {
                    handleGoodsGroupRotationPan(gesture)
                    return
                }
            }

            if viewModel.isAllShelvesSelectionActive {
                handleShelfGroupRotationPan(gesture)
                return
            }

            guard let targetEntity = rotationAdjustmentTargetEntity() else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                rotationPanStartOrientation = targetEntity.orientation
            case .changed:
                guard let startOrientation = rotationPanStartOrientation else {
                    return
                }

                let translation = gesture.translation(in: gesture.view)
                let yaw = simd_quatf(angle: Float(translation.x) * 0.01, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: Float(translation.y) * 0.01, axis: SIMD3<Float>(1, 0, 0))
                targetEntity.orientation = simd_normalize(yaw * pitch * startOrientation)
            case .ended, .cancelled, .failed:
                rotationPanStartOrientation = nil
                syncRotationAdjustedTargetToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        @objc private func handleShelfGroupPan(_ gesture: UIPanGestureRecognizer) {
            guard viewModel.isAllShelvesSelectionActive
                    || (viewModel.isMultipleSelectionActive && viewModel.selectedShelfIDs.isEmpty == false) else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                shelfGroupPanStartPositions = currentShelfLocalPositions()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = SIMD3<Float>(
                    Float(translation.x) * 0.0012,
                    0,
                    Float(translation.y) * 0.0012
                )

                for (shelfID, startPosition) in shelfGroupPanStartPositions {
                    guard let shelfEntity = shelfEntities[shelfID] else {
                        continue
                    }

                    shelfEntity.position = startPosition + delta
                }
            case .ended, .cancelled, .failed:
                shelfGroupPanStartPositions.removeAll()
                syncShelfTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        @objc private func handleGoodsGroupPan(_ gesture: UIPanGestureRecognizer) {
            guard viewModel.isMultipleSelectionActive,
                  viewModel.mode == .goodsEdit,
                  viewModel.selectedItemIDs.isEmpty == false else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                goodsGroupPanStartPositions = currentItemLocalPositions()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = SIMD3<Float>(
                    Float(translation.x) * 0.0012,
                    0,
                    Float(translation.y) * 0.0012
                )

                for (itemID, startPosition) in goodsGroupPanStartPositions {
                    guard let itemEntity = itemEntities[itemID] else {
                        continue
                    }

                    itemEntity.position = startPosition + delta
                }
            case .ended, .cancelled, .failed:
                goodsGroupPanStartPositions.removeAll()
                syncTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func handleShelfGroupHeightPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                shelfGroupHeightStartPositions = currentShelfLocalPositions()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let nextYOffset = -Float(translation.y) * 0.0012

                for (shelfID, startPosition) in shelfGroupHeightStartPositions {
                    guard let shelfEntity = shelfEntities[shelfID] else {
                        continue
                    }

                    var nextPosition = startPosition
                    nextPosition.y = min(max(startPosition.y + nextYOffset, -0.3), 1.5)
                    shelfEntity.position = nextPosition
                }
            case .ended, .cancelled, .failed:
                shelfGroupHeightStartPositions.removeAll()
                syncShelfTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func handleGoodsGroupHeightPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                goodsGroupHeightStartPositions = currentItemLocalPositions()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let nextYOffset = -Float(translation.y) * 0.0012

                for (itemID, startPosition) in goodsGroupHeightStartPositions {
                    guard let itemEntity = itemEntities[itemID] else {
                        continue
                    }

                    var nextPosition = startPosition
                    nextPosition.y = min(max(startPosition.y + nextYOffset, -0.3), 1.5)
                    itemEntity.position = nextPosition
                }
            case .ended, .cancelled, .failed:
                goodsGroupHeightStartPositions.removeAll()
                syncTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func handleShelfGroupRotationPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                shelfGroupRotationStartOrientations = currentShelfLocalOrientations()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let yaw = simd_quatf(angle: Float(translation.x) * 0.01, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: Float(translation.y) * 0.01, axis: SIMD3<Float>(1, 0, 0))

                for (shelfID, startOrientation) in shelfGroupRotationStartOrientations {
                    guard let shelfEntity = shelfEntities[shelfID] else {
                        continue
                    }

                    shelfEntity.orientation = simd_normalize(yaw * pitch * startOrientation)
                }
            case .ended, .cancelled, .failed:
                shelfGroupRotationStartOrientations.removeAll()
                syncShelfTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func handleGoodsGroupRotationPan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                goodsGroupRotationStartOrientations = currentItemLocalOrientations()
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let yaw = simd_quatf(angle: Float(translation.x) * 0.01, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: Float(translation.y) * 0.01, axis: SIMD3<Float>(1, 0, 0))

                for (itemID, startOrientation) in goodsGroupRotationStartOrientations {
                    guard let itemEntity = itemEntities[itemID] else {
                        continue
                    }

                    itemEntity.orientation = simd_normalize(yaw * pitch * startOrientation)
                }
            case .ended, .cancelled, .failed:
                goodsGroupRotationStartOrientations.removeAll()
                syncTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        @objc private func handleGoodsPinch(_ gesture: UIPinchGestureRecognizer) {
            if viewModel.isMultipleSelectionActive, viewModel.mode == .goodsEdit, viewModel.selectedItemIDs.isEmpty == false {
                handleGoodsGroupPinch(gesture)
                return
            }

            guard let selectedItemID = viewModel.selectedItemID,
                  let targetEntity = itemEntities[selectedItemID],
                  viewModel.mode == .goodsEdit,
                  viewModel.goodsMoveMode == .horizontalPlane else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                goodsPinchStartScale = targetEntity.scale
            case .changed:
                guard let startScale = goodsPinchStartScale else {
                    return
                }

                let nextScale = simd_clamp(startScale * Float(gesture.scale), SIMD3<Float>(repeating: 0.2), SIMD3<Float>(repeating: 4.0))
                targetEntity.scale = nextScale
            case .ended, .cancelled, .failed:
                goodsPinchStartScale = nil
                syncTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func handleGoodsGroupPinch(_ gesture: UIPinchGestureRecognizer) {
            guard viewModel.mode == .goodsEdit,
                  viewModel.selectedItemIDs.isEmpty == false,
                  viewModel.goodsMoveMode == .horizontalPlane else {
                return
            }

            switch gesture.state {
            case .began:
                viewModel.captureUndoSnapshot(includeImageData: false)
                goodsGroupScaleStartScales = currentItemLocalScales()
            case .changed:
                for (itemID, startScale) in goodsGroupScaleStartScales {
                    guard let itemEntity = itemEntities[itemID] else {
                        continue
                    }

                    let nextScale = simd_clamp(startScale * Float(gesture.scale), SIMD3<Float>(repeating: 0.2), SIMD3<Float>(repeating: 4.0))
                    itemEntity.scale = nextScale
                }
            case .ended, .cancelled, .failed:
                goodsGroupScaleStartScales.removeAll()
                syncTransformsToModel()
                viewModel.requestSave()
            default:
                break
            }
        }

        private func heightAdjustmentTargetEntity() -> ModelEntity? {
            if viewModel.mode == .shelfEdit,
               viewModel.shelfMoveMode == .height,
               let selectedShelfID = viewModel.selectedShelfID {
                return shelfEntities[selectedShelfID]
            }

            if viewModel.mode == .goodsEdit,
               viewModel.goodsMoveMode == .height,
               let selectedItemID = viewModel.selectedItemID {
                return itemEntities[selectedItemID]
            }

            return nil
        }

        private func rotationAdjustmentTargetEntity() -> ModelEntity? {
            if viewModel.mode == .shelfEdit,
               viewModel.shelfMoveMode == .rotation,
               let selectedShelfID = viewModel.selectedShelfID {
                return shelfEntities[selectedShelfID]
            }

            if viewModel.mode == .goodsEdit,
               viewModel.goodsMoveMode == .rotation,
               let selectedItemID = viewModel.selectedItemID {
                return itemEntities[selectedItemID]
            }

            return nil
        }

        private func syncHeightAdjustedTargetToModel() {
            if viewModel.mode == .shelfEdit {
                syncShelfTransformsToModel()
            } else if viewModel.mode == .goodsEdit {
                syncTransformsToModel()
            }
        }

        private func syncRotationAdjustedTargetToModel() {
            if viewModel.mode == .shelfEdit {
                syncShelfTransformsToModel()
            } else if viewModel.mode == .goodsEdit {
                syncTransformsToModel()
            }
        }

        private func selectObject(at point: CGPoint, in arView: ARView) {
            let hitEntity = arView.entity(at: point)

            if viewModel.isMultipleSelectionActive {
                if let itemID = itemID(for: hitEntity) {
                    viewModel.selectItem(id: itemID)
                    updateGestureAvailability()
                    updateSelectionOutline()
                    return
                }

                if let shelfID = shelfID(for: hitEntity) {
                    viewModel.selectShelf(id: shelfID)
                    updateGestureAvailability()
                    updateSelectionOutline()
                    return
                }

                if viewModel.hasActiveSelection {
                    viewModel.selectShelf(id: nil)
                    updateGestureAvailability()
                    updateSelectionOutline()
                }
                return
            }

            if viewModel.isAllShelvesSelectionActive {
                if hitEntity == nil, viewModel.selectedTarget != nil {
                    viewModel.selectShelf(id: nil)
                    updateGestureAvailability()
                    updateSelectionOutline()
                }
                return
            }

            if viewModel.mode == .goodsEdit, let itemID = itemID(for: hitEntity) {
                viewModel.selectItem(id: itemID)
                updateGestureAvailability()
                updateSelectionOutline()
                return
            }

            if viewModel.mode == .shelfEdit, let shelfID = shelfID(for: hitEntity) {
                viewModel.selectShelf(id: shelfID)
                updateGestureAvailability()
                updateSelectionOutline()
                return
            }

            guard isInterfaceHidden == false else {
                return
            }

            if viewModel.selectedTarget != nil {
                switch viewModel.mode {
                case .goodsEdit:
                    viewModel.selectItem(id: nil)
                case .shelfEdit:
                    viewModel.selectShelf(id: nil)
                case .placement:
                    break
                }
                updateGestureAvailability()
                updateSelectionOutline()
            }
        }

        private func placeShelf(_ shelf: Shelf, with transform: simd_float4x4, in arView: ARView) {
            let anchor = AnchorEntity(world: transform)
            let shelfEntity = ShelfEntityFactory.makeShelf(template: shelf.template)
            shelfEntity.name = shelf.id.uuidString
            anchor.addChild(shelfEntity)
            arView.scene.addAnchor(anchor)
            anchorEntities[shelf.id] = anchor
            shelfEntities[shelf.id] = shelfEntity
            shelfGestureRecognizers[shelf.id] = arView.installGestures([.translation, .rotation, .scale], for: shelfEntity)
            updateGestureAvailability()
        }

        private func restoreSavedItems(for shelf: Shelf) {
            guard let shelfEntity = shelfEntities[shelf.id] else {
                return
            }

            for item in shelf.items.sorted(by: { $0.slotIndex < $1.slotIndex }) {
                guard itemEntities[item.id] == nil else {
                    continue
                }

                switch item.contentType {
                case .image:
                    guard let image = ImageStore.load(path: item.imagePath) else {
                        continue
                    }

                    addImageItemEntity(for: item, image: image, to: shelfEntity, installGestures: true)
                case .model3D:
                    guard let modelPath = item.modelPath else {
                        continue
                    }

                    addModelItemEntity(for: item, modelPath: modelPath, to: shelfEntity, installGestures: true)
                }
            }
        }

        private func addImageItemEntity(for item: PlacedItem, image: UIImage, to shelfEntity: ModelEntity, installGestures: Bool) {
            let entity = GoodsEntityFactory.makeGoodsEntity(image: image, cacheKey: item.imagePath)
            let collisionSize = GoodsEntityFactory.size(for: image)
            let snapshot = item.transformSnapshot
            entity.position = snapshot.position
            entity.orientation = snapshot.quaternion
            entity.scale = snapshot.scale
            entity.name = item.id.uuidString
            shelfEntity.addChild(entity)
            itemEntities[item.id] = entity
            itemCollisionSizes[item.id] = collisionSize
            itemCollisionCenters[item.id] = .zero

            if installGestures, let arView {
                let recognizers = arView.installGestures([.translation, .rotation, .scale], for: entity)
                itemGestureRecognizers[item.id] = recognizers
                registerItemUndoTracking(recognizers: recognizers)
                updateCollisionAvailability()
                updateGestureAvailability()
            }
        }

        private func addModelItemEntity(for item: PlacedItem, modelPath: String, to shelfEntity: ModelEntity, installGestures: Bool) {
            guard let modelURL = ScannedModelStore.url(forRelativePath: modelPath),
                  let modelGoods = ModelGoodsEntityFactory.makeModelEntity(url: modelURL) else {
                viewModel.statusMessage = "3Dモデルを読み込めませんでした。"
                return
            }

            let entity = modelGoods.entity
            let snapshot = item.transformSnapshot
            entity.position = snapshot.position
            entity.orientation = snapshot.quaternion
            entity.scale = snapshot.scale
            entity.name = item.id.uuidString
            shelfEntity.addChild(entity)
            itemEntities[item.id] = entity
            itemCollisionSizes[item.id] = modelGoods.collisionSize
            itemCollisionCenters[item.id] = modelGoods.collisionCenter

            if installGestures, let arView {
                let recognizers = arView.installGestures([.translation, .rotation, .scale], for: entity)
                itemGestureRecognizers[item.id] = recognizers
                registerItemUndoTracking(recognizers: recognizers)
                updateCollisionAvailability()
                updateGestureAvailability()
            }
        }

        private func registerItemUndoTracking(recognizers: [EntityGestureRecognizer]) {
            for recognizer in recognizers {
                recognizer.addTarget(self, action: #selector(handleItemEntityGesture(_:)))
            }
        }

        @objc private func handleItemEntityGesture(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                if activeItemGestureCount == 0 {
                    viewModel.captureUndoSnapshot(includeImageData: false)
                }
                activeItemGestureCount += 1
            case .ended, .cancelled, .failed:
                activeItemGestureCount = max(activeItemGestureCount - 1, 0)
                if activeItemGestureCount == 0 {
                    syncTransformsToModel()
                    viewModel.requestSave()
                }
            default:
                break
            }
        }

        private func itemID(for entity: Entity?) -> UUID? {
            var currentEntity = entity

            while let entity = currentEntity {
                if let itemID = UUID(uuidString: entity.name), itemEntities[itemID] != nil {
                    return itemID
                }

                currentEntity = entity.parent
            }

            return nil
        }

        private func shelfID(for entity: Entity?) -> UUID? {
            var currentEntity = entity

            while let entity = currentEntity {
                if let shelfID = UUID(uuidString: entity.name), shelfEntities[shelfID] != nil {
                    return shelfID
                }

                currentEntity = entity.parent
            }

            return nil
        }

        private func updateGestureAvailability() {
            let isAllShelvesSelected = viewModel.isAllShelvesSelectionActive
            let isMultipleSelectionActive = viewModel.isMultipleSelectionActive
            let selectedShelfIDs = viewModel.selectedShelfIDs
            let selectedItemIDs = viewModel.selectedItemIDs
            let hasSelectedShelfTargets = selectedShelfIDs.isEmpty == false || isAllShelvesSelected
            let hasSelectedItemTargets = selectedItemIDs.isEmpty == false
            let isShelfHeightAdjustment = viewModel.mode == .shelfEdit
                && viewModel.shelfMoveMode == .height
                && (isMultipleSelectionActive ? hasSelectedShelfTargets : (viewModel.selectedShelfID != nil || isAllShelvesSelected))
            let isShelfHorizontalMovement = viewModel.mode == .shelfEdit
                && viewModel.shelfMoveMode == .horizontalPlane
                && (isMultipleSelectionActive ? hasSelectedShelfTargets : isAllShelvesSelected)
            let isShelfRotationAdjustment = viewModel.mode == .shelfEdit
                && viewModel.shelfMoveMode == .rotation
                && (isMultipleSelectionActive ? hasSelectedShelfTargets : (viewModel.selectedShelfID != nil || isAllShelvesSelected))
            let isGoodsHeightAdjustment = viewModel.mode == .goodsEdit
                && viewModel.goodsMoveMode == .height
                && (isMultipleSelectionActive ? hasSelectedItemTargets : viewModel.selectedItemID != nil)
            let isGoodsRotationAdjustment = viewModel.mode == .goodsEdit
                && viewModel.goodsMoveMode == .rotation
                && (isMultipleSelectionActive ? hasSelectedItemTargets : viewModel.selectedItemID != nil)
            let isGlobalGoodsPinchEnabled = viewModel.mode == .goodsEdit
                && viewModel.goodsMoveMode == .horizontalPlane
                && (isMultipleSelectionActive ? hasSelectedItemTargets : viewModel.selectedItemID != nil)
            let isGoodsHorizontalMovement = viewModel.mode == .goodsEdit
                && viewModel.goodsMoveMode == .horizontalPlane
                && (isMultipleSelectionActive ? hasSelectedItemTargets : viewModel.selectedItemID != nil)

            for (shelfID, recognizers) in shelfGestureRecognizers {
                let isSelectedShelf = viewModel.mode == .shelfEdit
                    && isMultipleSelectionActive == false
                    && isAllShelvesSelected == false
                    && viewModel.selectedTarget == .shelf(shelfID)
                recognizers.forEach { recognizer in
                    recognizer.isEnabled = isSelectedShelf
                        && isShelfHeightAdjustment == false
                        && isShelfRotationAdjustment == false
                }
            }
            shelfGroupPanGesture?.isEnabled = isShelfHorizontalMovement
            goodsGroupPanGesture?.isEnabled = isGoodsHorizontalMovement
            heightPanGesture?.isEnabled = isShelfHeightAdjustment || isGoodsHeightAdjustment
            rotationPanGesture?.isEnabled = isShelfRotationAdjustment || isGoodsRotationAdjustment
            goodsPinchGesture?.isEnabled = isGlobalGoodsPinchEnabled

            for (itemID, recognizers) in itemGestureRecognizers {
                let isSelectedItem = viewModel.mode == .goodsEdit
                    && isMultipleSelectionActive == false
                    && viewModel.selectedTarget == ARShelfSelectionTarget.item(itemID)
                recognizers.forEach { recognizer in
                    recognizer.isEnabled = isSelectedItem
                        && isGoodsHeightAdjustment == false
                        && isGoodsRotationAdjustment == false
                }
            }
        }

        private func updateCollisionAvailability() {
            let isShelfCollisionEnabled = viewModel.mode == .shelfEdit
            let areItemCollisionsEnabled = viewModel.mode == .goodsEdit

            setShelfCollisionEnabled(isShelfCollisionEnabled)

            for (itemID, entity) in itemEntities {
                let size = itemCollisionSizes[itemID] ?? GoodsEntityFactory.defaultSize
                let center = itemCollisionCenters[itemID] ?? .zero
                setCollision(on: entity, isEnabled: areItemCollisionsEnabled, size: size, center: center)
            }
        }

        private func setShelfCollisionEnabled(_ isEnabled: Bool) {
            for entity in shelfEntities.values {
                setCollision(on: entity, isEnabled: isEnabled, size: ShelfEntityFactory.collisionSize)
            }
        }

        private func setCollision(
            on entity: ModelEntity,
            isEnabled: Bool,
            size: SIMD3<Float>,
            center: SIMD3<Float> = .zero
        ) {
            let shapes: [ShapeResource] = isEnabled
                ? [.generateBox(size: size).offsetBy(translation: center)]
                : []
            entity.components.set(CollisionComponent(shapes: shapes))
        }

        private func updateSelectionOutline() {
            if isInterfaceHidden {
                clearSelectionOutline()
                return
            }

            let outlineTargets = currentOutlineTargets()
            guard outlinedTarget != viewModel.selectedTarget || outlinedSelectionTargets != outlineTargets else {
                return
            }

            clearSelectionOutline()
            var didAddOutline = false

            for target in outlineTargets {
                switch target {
                case let .shelf(shelfID):
                    guard let shelfEntity = shelfEntities[shelfID] else {
                        continue
                    }

                    let outline = SelectionOutlineFactory.makeOutline(
                        size: SIMD3<Float>(0.84, 0.30, 0.22),
                        center: SIMD3<Float>(0, 0.08, 0),
                        color: UIColor.systemBlue
                    )
                    shelfEntity.addChild(outline)
                    selectionOutlines.append(outline)
                    didAddOutline = true
                case let .item(itemID):
                    guard let itemEntity = itemEntities[itemID],
                          let item = viewModel.room.shelves.flatMap(\.items).first(where: { $0.id == itemID }) else {
                        continue
                    }

                    let outlineSize = itemCollisionSizes[itemID]
                        ?? (item.contentType == .model3D ? ModelGoodsEntityFactory.defaultCollisionSize : GoodsEntityFactory.size(forImageAt: item.imagePath))
                    let outlineCenter = itemCollisionCenters[itemID] ?? .zero
                    let outline = SelectionOutlineFactory.makeOutline(
                        size: outlineSize,
                        center: outlineCenter,
                        color: UIColor.systemBlue
                    )
                    itemEntity.addChild(outline)
                    selectionOutlines.append(outline)
                    didAddOutline = true
                case .allShelves:
                    continue
                }
            }

            guard didAddOutline else {
                outlinedTarget = nil
                outlinedSelectionTargets.removeAll()
                return
            }

            outlinedTarget = viewModel.selectedTarget
            outlinedSelectionTargets = outlineTargets
        }

        private func clearSelectionOutline() {
            selectionOutlines.forEach { $0.removeFromParent() }
            selectionOutlines.removeAll()
            outlinedTarget = nil
            outlinedSelectionTargets.removeAll()
        }

        private func currentOutlineTargets() -> [ARShelfSelectionTarget] {
            if viewModel.isMultipleSelectionActive {
                return viewModel.activeSelectionTargets
            }

            switch viewModel.selectedTarget {
            case let .shelf(shelfID):
                return [.shelf(shelfID)]
            case let .item(itemID):
                return [.item(itemID)]
            case .allShelves:
                return viewModel.placedShelves.map { .shelf($0.id) }
            case nil:
                return []
            }
        }

        private func currentShelfLocalPositions() -> [UUID: SIMD3<Float>] {
            let shelfIDs: [UUID]
            if viewModel.isMultipleSelectionActive {
                shelfIDs = viewModel.selectedShelfIDs
            } else if viewModel.isAllShelvesSelectionActive {
                shelfIDs = viewModel.placedShelves.map(\.id)
            } else if let selectedShelfID = viewModel.selectedShelfID {
                shelfIDs = [selectedShelfID]
            } else {
                shelfIDs = []
            }

            return Dictionary(uniqueKeysWithValues: shelfIDs.compactMap { shelfID in
                guard let shelfEntity = shelfEntities[shelfID] else {
                    return nil
                }

                return (shelfID, shelfEntity.position)
            })
        }

        private func currentShelfLocalOrientations() -> [UUID: simd_quatf] {
            let shelfIDs: [UUID]
            if viewModel.isMultipleSelectionActive {
                shelfIDs = viewModel.selectedShelfIDs
            } else if viewModel.isAllShelvesSelectionActive {
                shelfIDs = viewModel.placedShelves.map(\.id)
            } else if let selectedShelfID = viewModel.selectedShelfID {
                shelfIDs = [selectedShelfID]
            } else {
                shelfIDs = []
            }

            return Dictionary(uniqueKeysWithValues: shelfIDs.compactMap { shelfID in
                guard let shelfEntity = shelfEntities[shelfID] else {
                    return nil
                }

                return (shelfID, shelfEntity.orientation)
            })
        }

        private func currentItemLocalPositions() -> [UUID: SIMD3<Float>] {
            Dictionary(uniqueKeysWithValues: viewModel.selectedItemIDs.compactMap { itemID in
                guard let itemEntity = itemEntities[itemID] else {
                    return nil
                }

                return (itemID, itemEntity.position)
            })
        }

        private func currentItemLocalOrientations() -> [UUID: simd_quatf] {
            Dictionary(uniqueKeysWithValues: viewModel.selectedItemIDs.compactMap { itemID in
                guard let itemEntity = itemEntities[itemID] else {
                    return nil
                }

                return (itemID, itemEntity.orientation)
            })
        }

        private func currentItemLocalScales() -> [UUID: SIMD3<Float>] {
            Dictionary(uniqueKeysWithValues: viewModel.selectedItemIDs.compactMap { itemID in
                guard let itemEntity = itemEntities[itemID] else {
                    return nil
                }

                return (itemID, itemEntity.scale)
            })
        }

        func syncTransformsToModel() {
            for shelf in viewModel.room.shelves {
                for item in shelf.items {
                    guard let entity = itemEntities[item.id] else {
                        continue
                    }

                    item.transformSnapshot = TransformSnapshot(
                        position: entity.position,
                        rotation: entity.orientation,
                        scale: entity.scale
                    )
                }
            }
        }

        func syncShelfTransformsToModel() {
            for (shelfID, shelfEntity) in shelfEntities {
                guard let shelf = viewModel.room.shelves.first(where: { $0.id == shelfID }) else {
                    continue
                }

                let worldTransform = shelfEntity.transformMatrix(relativeTo: nil)
                shelf.anchorTransformData = MatrixCoder.encode(worldTransform)
                shelf.updatedAt = .now
            }
        }

        private func clearSceneContent() {
            shelfGestureRecognizers.values.flatMap { $0 }.forEach { $0.isEnabled = false }
            itemGestureRecognizers.values.flatMap { $0 }.forEach { $0.isEnabled = false }

            anchorEntities.values.forEach { $0.removeFromParent() }
            anchorEntities.removeAll()
            shelfEntities.removeAll()
            itemEntities.removeAll()
            itemCollisionSizes.removeAll()
            itemCollisionCenters.removeAll()
            shelfGestureRecognizers.removeAll()
            itemGestureRecognizers.removeAll()
            shelfGroupPanGesture?.isEnabled = false
            goodsGroupPanGesture?.isEnabled = false
            heightPanGesture?.isEnabled = false
            rotationPanGesture?.isEnabled = false
            goodsPinchGesture?.isEnabled = false
            shelfGroupPanStartPositions.removeAll()
            goodsGroupPanStartPositions.removeAll()
            shelfGroupHeightStartPositions.removeAll()
            goodsGroupHeightStartPositions.removeAll()
            shelfGroupRotationStartOrientations.removeAll()
            goodsGroupRotationStartOrientations.removeAll()
            goodsGroupScaleStartScales.removeAll()
            selectionOutlines.forEach { $0.removeFromParent() }
            selectionOutlines.removeAll()
            outlinedTarget = nil
            outlinedSelectionTargets.removeAll()
            activeItemGestureCount = 0
        }

        func notifyReadyIfNeeded() {
            guard didNotifyReady == false else {
                return
            }

            didNotifyReady = true
            onReady()
        }
    }
}

/// テンプレートごとの仮棚Entityを作ります。
enum ShelfEntityFactory {
    static let collisionSize = SIMD3<Float>(0.82, 0.28, 0.2)
    private static let shelfEntityCache: NSCache<NSString, ModelEntity> = {
        let cache = NSCache<NSString, ModelEntity>()
        cache.countLimit = 8
        return cache
    }()

    static func makeShelf(template: ShelfTemplate) -> ModelEntity {
        let cacheKey = template.rawValue as NSString
        if let cachedEntity = shelfEntityCache.object(forKey: cacheKey) {
            return cachedEntity.clone(recursive: true)
        }

        let root = ModelEntity()
        root.components.set(CollisionComponent(shapes: [.generateBox(size: collisionSize)]))

        switch template {
        case .wood:
            addBoard(to: root, position: [0, 0, 0], size: [0.72, 0.035, 0.16], color: UIColor(red: 0.56, green: 0.38, blue: 0.22, alpha: 1))
            addBoard(to: root, position: [0, 0.16, 0], size: [0.72, 0.028, 0.16], color: UIColor(red: 0.63, green: 0.45, blue: 0.28, alpha: 1))
            addBoard(to: root, position: [-0.36, 0.08, 0], size: [0.028, 0.18, 0.16], color: UIColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1))
            addBoard(to: root, position: [0.36, 0.08, 0], size: [0.028, 0.18, 0.16], color: UIColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1))
        case .glass:
            addBoard(to: root, position: [0, 0, 0], size: [0.72, 0.018, 0.16], color: UIColor(red: 0.78, green: 0.90, blue: 0.96, alpha: 0.45), roughness: 0.08, metallic: 0.0)
            addBoard(to: root, position: [0, 0.18, 0], size: [0.72, 0.018, 0.16], color: UIColor(red: 0.78, green: 0.90, blue: 0.96, alpha: 0.35), roughness: 0.08, metallic: 0.0)
            addBoard(to: root, position: [0, 0.09, 0.08], size: [0.72, 0.19, 0.012], color: UIColor(red: 0.82, green: 0.94, blue: 1.0, alpha: 0.22), roughness: 0.02, metallic: 0.0)
        case .wall:
            addBoard(to: root, position: [0, 0.08, 0.075], size: [0.78, 0.24, 0.025], color: UIColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1))
            addBoard(to: root, position: [0, 0, 0], size: [0.72, 0.03, 0.16], color: UIColor(red: 0.62, green: 0.58, blue: 0.50, alpha: 1))
            addBoard(to: root, position: [0, 0.15, 0], size: [0.72, 0.025, 0.14], color: UIColor(red: 0.70, green: 0.66, blue: 0.58, alpha: 1))
        }

        shelfEntityCache.setObject(root, forKey: cacheKey)
        return root.clone(recursive: true)
    }

    private static func addBoard(
        to root: Entity,
        position: SIMD3<Float>,
        size: SIMD3<Float>,
        color: UIColor,
        roughness: Float = 0.65,
        metallic: Float = 0.0
    ) {
        let mesh = MeshResource.generateBox(size: size)
        let material = SimpleMaterial(
            color: color,
            roughness: MaterialScalarParameter(floatLiteral: roughness),
            isMetallic: metallic > 0
        )
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.position = position
        root.addChild(model)
    }
}

/// 背景除去済み画像を薄い板状のグッズEntityへ変換します。
enum GoodsEntityFactory {
    private static let goodsEntityCache: NSCache<NSString, ModelEntity> = {
        let cache = NSCache<NSString, ModelEntity>()
        cache.countLimit = 24
        return cache
    }()

    static func makeGoodsEntity(image: UIImage, cacheKey: String? = nil) -> ModelEntity {
        if let cacheKey, let cachedEntity = goodsEntityCache.object(forKey: cacheKey as NSString) {
            return cachedEntity.clone(recursive: true)
        }

        let size = size(for: image)
        let root = ModelEntity()
        let planeMesh = MeshResource.generatePlane(width: size.x, height: size.y)
        let frontMaterial = textureMaterial(from: image, faceCulling: .back)
        let backMaterial = textureMaterial(
            from: image,
            faceCulling: .front
        )
        let frontEntity = ModelEntity(mesh: planeMesh, materials: [frontMaterial])
        let backEntity = ModelEntity(mesh: planeMesh, materials: [backMaterial])

        frontEntity.position.z = size.z / 2
        backEntity.position.z = -size.z / 2
        root.addChild(frontEntity)
        root.addChild(backEntity)
        makeSideEntities(from: image, size: size).forEach { root.addChild($0) }
        root.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))

        let resolvedCacheKey = cacheKey ?? makeImageCacheKey(for: image)
        goodsEntityCache.setObject(root, forKey: resolvedCacheKey as NSString)
        return root.clone(recursive: true)
    }

    static func makeGoodsEntity(image: UIImage) -> ModelEntity {
        makeGoodsEntity(image: image, cacheKey: nil)
    }

    static func size(forImageAt path: String) -> SIMD3<Float> {
        guard let image = ImageStore.load(path: path) else {
            return defaultSize
        }

        return size(for: image)
    }

    static var defaultSize: SIMD3<Float> {
        SIMD3<Float>(0.10, 0.10, 0.015)
    }

    static func size(for image: UIImage) -> SIMD3<Float> {
        let normalizedImage = image.normalizedForRendering()
        let aspectRatio = Float(normalizedImage.size.width / max(normalizedImage.size.height, 1))
        let aspectScale = sqrt(max(aspectRatio, 0.01))
        let baseSide: Float = 0.10
        let width = min(max(baseSide * aspectScale, 0.06), 0.18)
        let height = min(max(baseSide / aspectScale, 0.06), 0.18)
        let depth: Float = 0.015
        return SIMD3<Float>(width, height, depth)
    }

    private static func makeImageCacheKey(for image: UIImage) -> String {
        let normalizedImage = image.normalizedForRendering()
        guard let data = normalizedImage.pngData() else {
            return UUID().uuidString
        }

        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func textureMaterial(
        from image: UIImage,
        faceCulling: UnlitMaterial.FaceCulling = .none
    ) -> RealityKit.Material {
        let normalizedImage = image.normalizedForRendering()
        guard let cgImage = normalizedImage.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else {
            return SimpleMaterial(color: .white, roughness: 0.45, isMetallic: false)
        }

        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        material.opacityThreshold = 0.01
        material.faceCulling = faceCulling
        return material
    }

    private static func makeSideEntities(from image: UIImage, size: SIMD3<Float>) -> [ModelEntity] {
        guard let pixelData = pixelData(for: image) else {
            return []
        }

        let frontZ = size.z / 2
        let backZ = -size.z / 2
        let scaleX = size.x / Float(pixelData.width)
        let scaleY = size.y / Float(pixelData.height)

        let topTexture = makeTopBottomTexture(from: pixelData, edge: .top)
        let bottomTexture = makeTopBottomTexture(from: pixelData, edge: .bottom)
        let leftTexture = makeLeftRightTexture(from: pixelData, edge: .left)
        let rightTexture = makeLeftRightTexture(from: pixelData, edge: .right)

        let topEntity = makeSideEntity(
            mesh: makeSideMesh(
                from: pixelData,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                frontZ: frontZ,
                backZ: backZ,
                edge: .top
            ),
            texture: topTexture
        )
        let bottomEntity = makeSideEntity(
            mesh: makeSideMesh(
                from: pixelData,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                frontZ: frontZ,
                backZ: backZ,
                edge: .bottom
            ),
            texture: bottomTexture
        )
        let leftEntity = makeSideEntity(
            mesh: makeSideMesh(
                from: pixelData,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                frontZ: frontZ,
                backZ: backZ,
                edge: .left
            ),
            texture: leftTexture
        )
        let rightEntity = makeSideEntity(
            mesh: makeSideMesh(
                from: pixelData,
                size: size,
                scaleX: scaleX,
                scaleY: scaleY,
                frontZ: frontZ,
                backZ: backZ,
                edge: .right
            ),
            texture: rightTexture
        )

        return [topEntity, bottomEntity, leftEntity, rightEntity].compactMap { $0 }
    }

    private static func makeSideEntity(mesh: MeshResource?, texture: UIImage?) -> ModelEntity? {
        guard let mesh, let texture else {
            return nil
        }

        let material = textureMaterial(from: texture)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func makeSideMesh(
        from pixelData: ImagePixelData,
        size: SIMD3<Float>,
        scaleX: Float,
        scaleY: Float,
        frontZ: Float,
        backZ: Float,
        edge: SideEdge
    ) -> MeshResource? {
        var builder = MeshBuilder()
        let width = pixelData.width
        let height = pixelData.height

        for y in 0..<height {
            for x in 0..<width {
                guard pixelData.alpha(atX: x, y: y) > 8 else {
                    continue
                }

                switch edge {
                case .top:
                    guard y == 0 || pixelData.alpha(atX: x, y: y - 1) <= 8 else { continue }
                    let yWorld = size.y / 2 - Float(y) * scaleY
                    let x0 = -size.x / 2 + Float(x) * scaleX
                    let x1 = x0 + scaleX
                    builder.addQuad(
                        p0: [x0, yWorld, frontZ],
                        p1: [x1, yWorld, frontZ],
                        p2: [x1, yWorld, backZ],
                        p3: [x0, yWorld, backZ],
                        uv0: [Float(x) / Float(width), 0],
                        uv1: [Float(x + 1) / Float(width), 0],
                        uv2: [Float(x + 1) / Float(width), 1],
                        uv3: [Float(x) / Float(width), 1]
                    )
                case .bottom:
                    guard y == height - 1 || pixelData.alpha(atX: x, y: y + 1) <= 8 else { continue }
                    let yWorld = size.y / 2 - Float(y + 1) * scaleY
                    let x0 = -size.x / 2 + Float(x) * scaleX
                    let x1 = x0 + scaleX
                    builder.addQuad(
                        p0: [x0, yWorld, frontZ],
                        p1: [x1, yWorld, frontZ],
                        p2: [x1, yWorld, backZ],
                        p3: [x0, yWorld, backZ],
                        uv0: [Float(x) / Float(width), 0],
                        uv1: [Float(x + 1) / Float(width), 0],
                        uv2: [Float(x + 1) / Float(width), 1],
                        uv3: [Float(x) / Float(width), 1]
                    )
                case .left:
                    guard x == 0 || pixelData.alpha(atX: x - 1, y: y) <= 8 else { continue }
                    let xWorld = -size.x / 2 + Float(x) * scaleX
                    let y0 = size.y / 2 - Float(y) * scaleY
                    let y1 = y0 - scaleY
                    builder.addQuad(
                        p0: [xWorld, y0, frontZ],
                        p1: [xWorld, y1, frontZ],
                        p2: [xWorld, y1, backZ],
                        p3: [xWorld, y0, backZ],
                        uv0: [0, Float(y) / Float(height)],
                        uv1: [0, Float(y + 1) / Float(height)],
                        uv2: [1, Float(y + 1) / Float(height)],
                        uv3: [1, Float(y) / Float(height)]
                    )
                case .right:
                    guard x == width - 1 || pixelData.alpha(atX: x + 1, y: y) <= 8 else { continue }
                    let xWorld = -size.x / 2 + Float(x + 1) * scaleX
                    let y0 = size.y / 2 - Float(y) * scaleY
                    let y1 = y0 - scaleY
                    builder.addQuad(
                        p0: [xWorld, y0, frontZ],
                        p1: [xWorld, y1, frontZ],
                        p2: [xWorld, y1, backZ],
                        p3: [xWorld, y0, backZ],
                        uv0: [0, Float(y) / Float(height)],
                        uv1: [0, Float(y + 1) / Float(height)],
                        uv2: [1, Float(y + 1) / Float(height)],
                        uv3: [1, Float(y) / Float(height)]
                    )
                }
            }
        }

        guard builder.indices.isEmpty == false else {
            return nil
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(builder.positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(builder.uvs)
        descriptor.primitives = .triangles(builder.indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeTopBottomTexture(from pixelData: ImagePixelData, edge: TextureEdge) -> UIImage? {
        let textureHeight = 32
        let width = pixelData.width
        var pixels = [UInt8](repeating: 0, count: width * textureHeight * 4)
        let minimumAlpha: UInt8 = 244

        for x in 0..<width {
            let sampledColor = edge.sampledColor(from: pixelData, index: x)
            for y in 0..<textureHeight {
                let t = CGFloat(y) / CGFloat(max(textureHeight - 1, 1))
                let shade = CGFloat(0.92 + 0.08 * t)
                let mixed = lightenedColor(sampledColor, amount: 0.82)
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(clamping: Int(CGFloat(mixed.r) * shade))
                pixels[offset + 1] = UInt8(clamping: Int(CGFloat(mixed.g) * shade))
                pixels[offset + 2] = UInt8(clamping: Int(CGFloat(mixed.b) * shade))
                pixels[offset + 3] = max(sampledColor.a, minimumAlpha)
            }
        }

        return image(from: pixels, width: width, height: textureHeight)
    }

    private static func makeLeftRightTexture(from pixelData: ImagePixelData, edge: TextureEdge) -> UIImage? {
        let textureWidth = 32
        let height = pixelData.height
        var pixels = [UInt8](repeating: 0, count: textureWidth * height * 4)
        let minimumAlpha: UInt8 = 244

        for y in 0..<height {
            let sampledColor = edge.sampledColor(from: pixelData, index: y)
            for x in 0..<textureWidth {
                let t = CGFloat(x) / CGFloat(max(textureWidth - 1, 1))
                let shade = CGFloat(0.92 + 0.08 * t)
                let mixed = lightenedColor(sampledColor, amount: 0.82)
                let offset = (y * textureWidth + x) * 4
                pixels[offset] = UInt8(clamping: Int(CGFloat(mixed.r) * shade))
                pixels[offset + 1] = UInt8(clamping: Int(CGFloat(mixed.g) * shade))
                pixels[offset + 2] = UInt8(clamping: Int(CGFloat(mixed.b) * shade))
                pixels[offset + 3] = max(sampledColor.a, minimumAlpha)
            }
        }

        return image(from: pixels, width: textureWidth, height: height)
    }

    private static func image(from pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func pixelData(for image: UIImage) -> ImagePixelData? {
        let normalizedImage = image.normalizedForRendering()
        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ImagePixelData(width: width, height: height, pixels: pixels)
    }

    private static func lightenedColor(_ color: RGBAColor, amount: CGFloat) -> RGBAColor {
        let mix = min(max(amount, 0), 1)
        let inverse = 1 - mix
        return RGBAColor(
            r: UInt8(clamping: Int(CGFloat(color.r) * inverse + 255 * mix)),
            g: UInt8(clamping: Int(CGFloat(color.g) * inverse + 255 * mix)),
            b: UInt8(clamping: Int(CGFloat(color.b) * inverse + 255 * mix)),
            a: color.a
        )
    }
}

private struct ImagePixelData {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func alpha(atX x: Int, y: Int) -> UInt8 {
        pixels[pixelIndex(atX: x, y: y) + 3]
    }

    func sampledColor(atX x: Int, y: Int) -> RGBAColor {
        let index = pixelIndex(atX: x, y: y)
        return RGBAColor(
            r: pixels[index],
            g: pixels[index + 1],
            b: pixels[index + 2],
            a: pixels[index + 3]
        )
    }

    private func pixelIndex(atX x: Int, y: Int) -> Int {
        (y * width + x) * 4
    }
}

private struct RGBAColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private enum SideEdge {
    case top
    case bottom
    case left
    case right
}

private enum TextureEdge {
    case top
    case bottom
    case left
    case right

    func sampledColor(from pixelData: ImagePixelData, index: Int) -> RGBAColor {
        switch self {
        case .top:
            return sampledHorizontalEdgeColor(from: pixelData, column: index, searchFromTop: true)
        case .bottom:
            return sampledHorizontalEdgeColor(from: pixelData, column: index, searchFromTop: false)
        case .left:
            return sampledVerticalEdgeColor(from: pixelData, row: index, searchFromLeft: true)
        case .right:
            return sampledVerticalEdgeColor(from: pixelData, row: index, searchFromLeft: false)
        }
    }

    private func sampledHorizontalEdgeColor(
        from pixelData: ImagePixelData,
        column: Int,
        searchFromTop: Bool
    ) -> RGBAColor {
        if searchFromTop {
            for y in 0..<pixelData.height {
                if pixelData.alpha(atX: column, y: y) > 8 {
                    return pixelData.sampledColor(atX: column, y: y)
                }
            }
        } else {
            for y in stride(from: pixelData.height - 1, through: 0, by: -1) {
                if pixelData.alpha(atX: column, y: y) > 8 {
                    return pixelData.sampledColor(atX: column, y: y)
                }
            }
        }

        return RGBAColor(r: 160, g: 140, b: 120, a: 255)
    }

    private func sampledVerticalEdgeColor(
        from pixelData: ImagePixelData,
        row: Int,
        searchFromLeft: Bool
    ) -> RGBAColor {
        if searchFromLeft {
            for x in 0..<pixelData.width {
                if pixelData.alpha(atX: x, y: row) > 8 {
                    return pixelData.sampledColor(atX: x, y: row)
                }
            }
        } else {
            for x in stride(from: pixelData.width - 1, through: 0, by: -1) {
                if pixelData.alpha(atX: x, y: row) > 8 {
                    return pixelData.sampledColor(atX: x, y: row)
                }
            }
        }

        return RGBAColor(r: 160, g: 140, b: 120, a: 255)
    }
}

private struct MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    mutating func addQuad(
        p0: SIMD3<Float>,
        p1: SIMD3<Float>,
        p2: SIMD3<Float>,
        p3: SIMD3<Float>,
        uv0: SIMD2<Float>,
        uv1: SIMD2<Float>,
        uv2: SIMD2<Float>,
        uv3: SIMD2<Float>
    ) {
        guard let baseIndex = UInt32(exactly: positions.count) else {
            return
        }

        positions.append(contentsOf: [p0, p1, p2, p3])
        uvs.append(contentsOf: [uv0, uv1, uv2, uv3])
        indices.append(contentsOf: [
            baseIndex, baseIndex + 1, baseIndex + 2,
            baseIndex, baseIndex + 2, baseIndex + 3
        ])
    }
}

/// 保存済みUSDZを棚に置きやすいサイズの3DグッズEntityへ変換します。
enum ModelGoodsEntityFactory {
    static let defaultCollisionSize = SIMD3<Float>(0.14, 0.14, 0.14)
    private static let modelEntityCache: NSCache<NSString, CachedModelGoodsEntity> = {
        let cache = NSCache<NSString, CachedModelGoodsEntity>()
        cache.countLimit = 8
        return cache
    }()

    @MainActor
    static func makeModelEntity(url: URL) -> ModelGoodsEntity? {
        let cacheKey = url.standardizedFileURL.path as NSString
        if let cachedEntity = modelEntityCache.object(forKey: cacheKey) {
            return cachedEntity.makeValue()
        }

        guard let loadedEntity = try? Entity.load(contentsOf: url) else {
            return nil
        }

        let root = ModelEntity()
        var collisionSize = defaultCollisionSize
        var collisionCenter = SIMD3<Float>(0, defaultCollisionSize.y / 2, 0)

        let bounds = loadedEntity.visualBounds(relativeTo: loadedEntity)
        if bounds.isEmpty == false {
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            var normalizedScale: Float = 1.0
            if maxExtent > 0 {
                normalizedScale = min(0.12 / maxExtent, 1.0)
                loadedEntity.scale = SIMD3<Float>(repeating: normalizedScale)
            }

            let bottomAlignedCenter = SIMD3<Float>(
                bounds.center.x,
                bounds.min.y,
                bounds.center.z
            )
            loadedEntity.position = -bottomAlignedCenter * normalizedScale

            let trimmedSize = bounds.extents * normalizedScale
            collisionSize = SIMD3<Float>(
                max(trimmedSize.x, 0.02),
                max(trimmedSize.y, 0.02),
                max(trimmedSize.z, 0.02)
            )
            collisionCenter = SIMD3<Float>(
                0,
                collisionSize.y / 2,
                0
            )
        } else {
            loadedEntity.scale = SIMD3<Float>(repeating: 0.25)
        }

        root.components.set(
            CollisionComponent(shapes: [
                .generateBox(size: collisionSize).offsetBy(translation: collisionCenter)
            ])
        )
        root.addChild(loadedEntity)
        let value = ModelGoodsEntity(
            entity: root,
            collisionSize: collisionSize,
            collisionCenter: collisionCenter
        )
        let cachedValue = CachedModelGoodsEntity(value: value)
        modelEntityCache.setObject(cachedValue, forKey: cacheKey)
        return cachedValue.makeValue()
    }
}

final class CachedModelGoodsEntity: NSObject {
    private let entity: ModelEntity
    private let collisionSize: SIMD3<Float>
    private let collisionCenter: SIMD3<Float>

    init(value: ModelGoodsEntity) {
        entity = value.entity
        collisionSize = value.collisionSize
        collisionCenter = value.collisionCenter
    }

    func makeValue() -> ModelGoodsEntity {
        ModelGoodsEntity(
            entity: entity.clone(recursive: true),
            collisionSize: collisionSize,
            collisionCenter: collisionCenter
        )
    }
}

struct ModelGoodsEntity {
    let entity: ModelEntity
    let collisionSize: SIMD3<Float>
    let collisionCenter: SIMD3<Float>
}

/// 選択中Entityに取り付ける、細いBoxを組み合わせた選択枠です。
enum SelectionOutlineFactory {
    static func makeOutline(
        size: SIMD3<Float>,
        center: SIMD3<Float> = .zero,
        color: UIColor,
        lineWidth: Float = 0.004
    ) -> Entity {
        let root = Entity()
        root.position = center

        let safeSize = SIMD3<Float>(
            max(size.x, lineWidth),
            max(size.y, lineWidth),
            max(size.z, lineWidth)
        )
        let halfSize = safeSize / 2
        let material = UnlitMaterial(color: color.withAlphaComponent(0.95))
        let xPositions: [Float] = [-halfSize.x, halfSize.x]
        let yPositions: [Float] = [-halfSize.y, halfSize.y]
        let zPositions: [Float] = [-halfSize.z, halfSize.z]

        for y in yPositions {
            for z in zPositions {
                addLine(
                    to: root,
                    position: SIMD3<Float>(0, y, z),
                    size: SIMD3<Float>(safeSize.x, lineWidth, lineWidth),
                    material: material
                )
            }
        }

        for x in xPositions {
            for z in zPositions {
                addLine(
                    to: root,
                    position: SIMD3<Float>(x, 0, z),
                    size: SIMD3<Float>(lineWidth, safeSize.y, lineWidth),
                    material: material
                )
            }
        }

        for x in xPositions {
            for y in yPositions {
                addLine(
                    to: root,
                    position: SIMD3<Float>(x, y, 0),
                    size: SIMD3<Float>(lineWidth, lineWidth, safeSize.z),
                    material: material
                )
            }
        }

        return root
    }

    private static func addLine(
        to root: Entity,
        position: SIMD3<Float>,
        size: SIMD3<Float>,
        material: RealityKit.Material
    ) {
        let line = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        line.position = position
        root.addChild(line)
    }
}
