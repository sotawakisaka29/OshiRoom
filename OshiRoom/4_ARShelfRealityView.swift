import ARKit
import CryptoKit
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
        private var itemCollisionCenters: [UUID: SIMD3<Float>] = [:]
        private var shelfGestureRecognizers: [EntityGestureRecognizer] = []
        private var itemGestureRecognizers: [UUID: [EntityGestureRecognizer]] = [:]
        private var heightPanGesture: UIPanGestureRecognizer?
        private var heightPanStartY: Float = 0
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

            let heightPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleHeightPan(_:)))
            heightPanGesture.maximumNumberOfTouches = 1
            heightPanGesture.isEnabled = false
            arView.addGestureRecognizer(heightPanGesture)
            self.heightPanGesture = heightPanGesture
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
            itemCollisionCenters[selectedItemID] = nil
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
            switch pendingGoods.content {
            case .image(let image):
                addImageItemEntity(for: pendingGoods.item, image: image, installGestures: true)
            case .model3D(let modelPath):
                addModelItemEntity(for: pendingGoods.item, modelPath: modelPath, installGestures: true)
            }
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

        @objc private func handleHeightPan(_ gesture: UIPanGestureRecognizer) {
            guard let targetEntity = heightAdjustmentTargetEntity() else {
                return
            }

            switch gesture.state {
            case .began:
                heightPanStartY = targetEntity.position.y
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let nextY = heightPanStartY - Float(translation.y) * 0.0012
                targetEntity.position.y = min(max(nextY, -0.3), 1.5)
            case .ended, .cancelled, .failed:
                syncHeightAdjustedTargetToModel()
            default:
                break
            }
        }

        private func heightAdjustmentTargetEntity() -> ModelEntity? {
            if viewModel.mode == .shelfEdit,
               viewModel.shelfMoveMode == .height,
               viewModel.selectedTarget == ARShelfSelectionTarget.shelf {
                return shelfEntity
            }

            if viewModel.mode == .goodsEdit,
               viewModel.goodsMoveMode == .height,
               let selectedItemID = viewModel.selectedItemID {
                return itemEntities[selectedItemID]
            }

            return nil
        }

        private func syncHeightAdjustedTargetToModel() {
            if viewModel.mode == .shelfEdit {
                syncShelfTransformToModel()
            } else if viewModel.mode == .goodsEdit {
                syncTransformsToModel()
            }
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
                switch item.contentType {
                case .image:
                    guard let image = ImageStore.load(path: item.imagePath) else {
                        continue
                    }

                    addImageItemEntity(for: item, image: image, installGestures: true)
                case .model3D:
                    guard let modelPath = item.modelPath else {
                        continue
                    }

                    addModelItemEntity(for: item, modelPath: modelPath, installGestures: true)
                }
            }
        }

        private func addImageItemEntity(for item: PlacedItem, image: UIImage, installGestures: Bool) {
            guard let shelfEntity else {
                return
            }

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
                itemGestureRecognizers[item.id] = arView.installGestures([.translation, .rotation, .scale], for: entity)
                updateCollisionAvailability()
                updateGestureAvailability()
            }
        }

        private func addModelItemEntity(for item: PlacedItem, modelPath: String, installGestures: Bool) {
            guard let shelfEntity,
                  let modelURL = ScannedModelStore.url(forRelativePath: modelPath),
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
            let isShelfHeightAdjustment = isShelfSelected && viewModel.shelfMoveMode == .height
            let isGoodsHeightAdjustment = viewModel.mode == .goodsEdit
                && viewModel.goodsMoveMode == .height
                && viewModel.selectedItemID != nil

            shelfGestureRecognizers.forEach { recognizer in
                recognizer.isEnabled = isShelfSelected && isShelfHeightAdjustment == false
            }
            heightPanGesture?.isEnabled = isShelfHeightAdjustment || isGoodsHeightAdjustment

            for (itemID, recognizers) in itemGestureRecognizers {
                let isSelectedItem = viewModel.mode == .goodsEdit
                    && viewModel.selectedTarget == ARShelfSelectionTarget.item(itemID)
                recognizers.forEach { recognizer in
                    recognizer.isEnabled = isSelectedItem && isGoodsHeightAdjustment == false
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
            guard let shelfEntity else {
                return
            }

            setCollision(on: shelfEntity, isEnabled: isEnabled, size: ShelfEntityFactory.collisionSize)
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

                let outlineSize = itemCollisionSizes[itemID]
                    ?? (item.contentType == .model3D ? ModelGoodsEntityFactory.defaultCollisionSize : GoodsEntityFactory.size(forImageAt: item.imagePath))
                let outlineCenter = itemCollisionCenters[itemID] ?? .zero
                let outline = SelectionOutlineFactory.makeOutline(
                    size: outlineSize,
                    center: outlineCenter,
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
    private static let goodsEntityCache: NSCache<NSString, ModelEntity> = {
        let cache = NSCache<NSString, ModelEntity>()
        cache.countLimit = 40
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
        return root
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
        let height: Float = 0.10
        let aspectRatio = Float(normalizedImage.size.width / max(normalizedImage.size.height, 1))
        let width = max(height * aspectRatio, 0.06)
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

    @MainActor
    static func makeModelEntity(url: URL) -> ModelGoodsEntity? {
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
        return ModelGoodsEntity(
            entity: root,
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
