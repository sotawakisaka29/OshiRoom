import ARKit
import RealityKit
import SwiftData
import SwiftUI
import UIKit

/// SwiftUI画面の中でRealityKitのARViewを表示します。
struct ARShelfRealityView: UIViewRepresentable {
    let viewModel: ARShelfViewModel
    let modelContext: ModelContext
    let isInterfaceHidden: Bool
    let onRequestShowInterface: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            isInterfaceHidden: isInterfaceHidden,
            onRequestShowInterface: onRequestShowInterface
        )
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeARView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.isInterfaceHidden = isInterfaceHidden
        context.coordinator.onRequestShowInterface = onRequestShowInterface
        context.coordinator.updateMode(viewModel.mode)
        context.coordinator.restoreShelfIfNeeded(in: uiView)
        context.coordinator.consumePendingGoodsIfNeeded()
        context.coordinator.deleteIfNeeded(modelContext: modelContext)
        context.coordinator.saveIfNeeded(modelContext: modelContext)
    }

    final class Coordinator: NSObject {
        var viewModel: ARShelfViewModel
        var isInterfaceHidden: Bool
        var onRequestShowInterface: () -> Void
        private weak var arView: ARView?
        private var anchorEntity: AnchorEntity?
        private var shelfEntity: ModelEntity?
        private var itemEntities: [UUID: ModelEntity] = [:]
        private var itemCollisionSizes: [UUID: SIMD3<Float>] = [:]
        private var shelfGestureRecognizers: [EntityGestureRecognizer] = []
        private var itemGestureRecognizers: [UUID: [EntityGestureRecognizer]] = [:]
        private var selectionOutline: Entity?
        private var outlinedTarget: ARShelfSelectionTarget?
        private var handledPendingGoodsID: UUID?
        private var handledSaveRequestToken = 0
        private var handledDeleteRequestToken = 0
        private var hasRestoredShelf = false

        init(
            viewModel: ARShelfViewModel,
            isInterfaceHidden: Bool,
            onRequestShowInterface: @escaping () -> Void
        ) {
            self.viewModel = viewModel
            self.isInterfaceHidden = isInterfaceHidden
            self.onRequestShowInterface = onRequestShowInterface
        }

        func makeARView() -> ARView {
            let arView = ARView(frame: .zero)
            self.arView = arView
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.automaticallyConfigureSession = false

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            arView.session.run(configuration)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapGesture)
            return arView
        }

        func updateMode(_ mode: ARInteractionMode) {
            updateCollisionAvailability()
            updateGestureAvailability()
            updateSelectionOutline()
        }

        func restoreShelfIfNeeded(in arView: ARView) {
            guard hasRestoredShelf == false else {
                return
            }
            hasRestoredShelf = true

            guard let matrix = MatrixCoder.decode(viewModel.shelf.anchorTransformData) else {
                return
            }

            placeShelf(with: matrix, in: arView)
            restoreSavedItems()
            viewModel.statusMessage = "保存済みの棚を復元しました。"
        }

        func saveIfNeeded(modelContext: ModelContext) {
            guard handledSaveRequestToken != viewModel.saveRequestToken else {
                return
            }

            handledSaveRequestToken = viewModel.saveRequestToken
            syncTransformsToModel()
            syncShelfTransformToModel()
            _ = viewModel.save(modelContext: modelContext)
        }

        func deleteIfNeeded(modelContext: ModelContext) {
            guard handledDeleteRequestToken != viewModel.deleteRequestToken else {
                return
            }

            handledDeleteRequestToken = viewModel.deleteRequestToken
            guard let selectedItemID = viewModel.selectedItemID else {
                viewModel.statusMessage = "先に削除したいグッズをタップして選択してください。"
                return
            }

            itemEntities[selectedItemID]?.removeFromParent()
            itemEntities[selectedItemID] = nil
            itemCollisionSizes[selectedItemID] = nil
            itemGestureRecognizers[selectedItemID]?.forEach { $0.isEnabled = false }
            itemGestureRecognizers[selectedItemID] = nil
            clearSelectionOutline()
            syncTransformsToModel()
            _ = viewModel.deleteSelected(modelContext: modelContext)
            updateGestureAvailability()
        }

        func consumePendingGoodsIfNeeded() {
            guard let pendingGoods = viewModel.pendingGoods else {
                return
            }

            guard handledPendingGoodsID != pendingGoods.item.id else {
                return
            }

            guard shelfEntity != nil else {
                viewModel.statusMessage = "先に床をタップして棚を配置してください。"
                return
            }

            handledPendingGoodsID = pendingGoods.item.id
            addItemEntity(for: pendingGoods.item, image: pendingGoods.image, installGestures: true)
            viewModel.pendingGoods = nil
            updateGestureAvailability()
            updateSelectionOutline()
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else {
                return
            }

            let point = gesture.location(in: arView)
            if isInterfaceHidden, arView.entity(at: point) == nil {
                onRequestShowInterface()
                return
            }

            if shelfEntity != nil {
                selectObject(at: point, in: arView)
                return
            }

            guard viewModel.mode == .placement else {
                return
            }

            guard let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else {
                viewModel.statusMessage = "床がまだ見つかっていません。ゆっくり部屋を映してください。"
                return
            }

            placeShelf(with: result.worldTransform, in: arView)
            viewModel.shelf.anchorTransformData = MatrixCoder.encode(result.worldTransform)
            viewModel.switchMode(.shelfEdit)
            viewModel.selectShelf()
            updateCollisionAvailability()
            updateGestureAvailability()
            updateSelectionOutline()
        }

        private func selectObject(at point: CGPoint, in arView: ARView) {
            let hitEntity = arView.entity(at: point)

            if viewModel.mode == .goodsEdit, let itemID = itemID(for: hitEntity) {
                viewModel.selectItem(id: itemID)
                updateGestureAvailability()
                updateSelectionOutline()
                return
            }

            if viewModel.mode == .shelfEdit, isShelfHit(hitEntity) {
                viewModel.selectShelf()
                updateGestureAvailability()
                updateSelectionOutline()
                return
            }

            guard isInterfaceHidden == false else {
                return
            }

            if viewModel.selectedTarget != nil {
                viewModel.selectItem(id: nil)
                updateGestureAvailability()
                updateSelectionOutline()
            }
        }

        private func placeShelf(with transform: simd_float4x4, in arView: ARView) {
            let anchor = AnchorEntity(world: transform)
            let shelf = ShelfEntityFactory.makeShelf(template: viewModel.shelf.template)
            anchor.addChild(shelf)
            arView.scene.addAnchor(anchor)
            anchorEntity = anchor
            shelfEntity = shelf
            shelfGestureRecognizers = arView.installGestures([.translation, .rotation, .scale], for: shelf)
            updateGestureAvailability()
        }

        private func restoreSavedItems() {
            for item in viewModel.sortedItems {
                guard let image = ImageStore.load(path: item.imagePath) else {
                    continue
                }

                addItemEntity(for: item, image: image, installGestures: true)
            }
        }

        private func addItemEntity(for item: PlacedItem, image: UIImage, installGestures: Bool) {
            guard let shelfEntity else {
                return
            }

            let entity = GoodsEntityFactory.makeGoodsEntity(image: image)
            let collisionSize = GoodsEntityFactory.size(for: image)
            let snapshot = item.transformSnapshot
            entity.position = snapshot.position
            entity.orientation = snapshot.quaternion
            entity.scale = snapshot.scale
            entity.name = item.id.uuidString
            shelfEntity.addChild(entity)
            itemEntities[item.id] = entity
            itemCollisionSizes[item.id] = collisionSize

            if installGestures, let arView {
                itemGestureRecognizers[item.id] = arView.installGestures([.translation, .rotation, .scale], for: entity)
                updateCollisionAvailability()
                updateGestureAvailability()
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

        private func isShelfHit(_ entity: Entity?) -> Bool {
            guard let shelfEntity else {
                return false
            }

            var currentEntity = entity

            while let entity = currentEntity {
                if entity === shelfEntity {
                    return true
                }

                currentEntity = entity.parent
            }

            return false
        }

        private func updateGestureAvailability() {
            let isShelfSelected = viewModel.mode == .shelfEdit
                && viewModel.selectedTarget == ARShelfSelectionTarget.shelf

            shelfGestureRecognizers.forEach { recognizer in
                recognizer.isEnabled = isShelfSelected
            }

            for (itemID, recognizers) in itemGestureRecognizers {
                let isSelectedItem = viewModel.mode == .goodsEdit
                    && viewModel.selectedTarget == ARShelfSelectionTarget.item(itemID)
                recognizers.forEach { recognizer in
                    recognizer.isEnabled = isSelectedItem
                }
            }
        }

        private func updateCollisionAvailability() {
            let isShelfCollisionEnabled = viewModel.mode == .shelfEdit
            let areItemCollisionsEnabled = viewModel.mode == .goodsEdit

            setShelfCollisionEnabled(isShelfCollisionEnabled)

            for (itemID, entity) in itemEntities {
                let size = itemCollisionSizes[itemID] ?? GoodsEntityFactory.defaultSize
                setCollision(on: entity, isEnabled: areItemCollisionsEnabled, size: size)
            }
        }

        private func setShelfCollisionEnabled(_ isEnabled: Bool) {
            guard let shelfEntity else {
                return
            }

            setCollision(on: shelfEntity, isEnabled: isEnabled, size: ShelfEntityFactory.collisionSize)
        }

        private func setCollision(on entity: ModelEntity, isEnabled: Bool, size: SIMD3<Float>) {
            let shapes: [ShapeResource] = isEnabled ? [.generateBox(size: size)] : []
            entity.components.set(CollisionComponent(shapes: shapes))
        }

        private func updateSelectionOutline() {
            guard outlinedTarget != viewModel.selectedTarget else {
                return
            }

            clearSelectionOutline()

            switch viewModel.selectedTarget {
            case .some(ARShelfSelectionTarget.shelf):
                guard let shelfEntity else {
                    return
                }

                let outline = SelectionOutlineFactory.makeOutline(
                    size: SIMD3<Float>(0.84, 0.30, 0.22),
                    center: SIMD3<Float>(0, 0.08, 0),
                    color: UIColor.systemBlue
                )
                shelfEntity.addChild(outline)
                selectionOutline = outline
                outlinedTarget = ARShelfSelectionTarget.shelf
            case let .some(ARShelfSelectionTarget.item(itemID)):
                guard let itemEntity = itemEntities[itemID],
                      let item = viewModel.shelf.items.first(where: { $0.id == itemID }) else {
                    return
                }

                let outline = SelectionOutlineFactory.makeOutline(
                    size: GoodsEntityFactory.size(forImageAt: item.imagePath),
                    color: UIColor.systemBlue
                )
                itemEntity.addChild(outline)
                selectionOutline = outline
                outlinedTarget = ARShelfSelectionTarget.item(itemID)
            case nil:
                break
            }
        }

        private func clearSelectionOutline() {
            selectionOutline?.removeFromParent()
            selectionOutline = nil
            outlinedTarget = nil
        }

        func syncTransformsToModel() {
            for item in viewModel.shelf.items {
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

        func syncShelfTransformToModel() {
            guard let shelfEntity else {
                return
            }

            let worldTransform = shelfEntity.transformMatrix(relativeTo: nil)
            viewModel.shelf.anchorTransformData = MatrixCoder.encode(worldTransform)
        }
    }
}

/// テンプレートごとの仮棚Entityを作ります。
enum ShelfEntityFactory {
    static let collisionSize = SIMD3<Float>(0.82, 0.28, 0.2)

    static func makeShelf(template: ShelfTemplate) -> ModelEntity {
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

        return root
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
    static func makeGoodsEntity(image: UIImage) -> ModelEntity {
        let size = size(for: image)
        let mesh = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z)

        let material = textureMaterial(from: image)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        return entity
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
        let height: Float = 0.10
        let aspectRatio = Float(normalizedImage.size.width / max(normalizedImage.size.height, 1))
        let width = max(height * aspectRatio, 0.06)
        let depth: Float = 0.015
        return SIMD3<Float>(width, height, depth)
    }

    private static func textureMaterial(from image: UIImage) -> RealityKit.Material {
        let normalizedImage = image.normalizedForRendering()
        guard let cgImage = normalizedImage.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else {
            return SimpleMaterial(color: .white, roughness: 0.45, isMetallic: false)
        }

        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        return material
    }
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
