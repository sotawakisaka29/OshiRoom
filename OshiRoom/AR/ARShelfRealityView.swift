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
            shelfEntity?.isEnabled = true
            for entity in itemEntities.values {
                entity.isEnabled = true
            }
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
            syncTransformsToModel()
            _ = viewModel.deleteSelected(modelContext: modelContext)
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
                selectItem(at: point, in: arView)
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
            viewModel.statusMessage = "棚を配置しました。棚をドラッグ、ピンチ、回転して位置を調整できます。"
        }

        private func selectItem(at point: CGPoint, in arView: ARView) {
            guard let entity = arView.entity(at: point),
                  let itemID = UUID(uuidString: entity.name),
                  itemEntities[itemID] != nil else {
                viewModel.selectItem(id: nil)
                return
            }

            viewModel.selectItem(id: itemID)
        }

        private func placeShelf(with transform: simd_float4x4, in arView: ARView) {
            let anchor = AnchorEntity(world: transform)
            let shelf = ShelfEntityFactory.makeShelf(template: viewModel.shelf.template)
            anchor.addChild(shelf)
            arView.scene.addAnchor(anchor)
            anchorEntity = anchor
            shelfEntity = shelf
            arView.installGestures([.translation, .rotation, .scale], for: shelf)
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
            let snapshot = item.transformSnapshot
            entity.position = snapshot.position
            entity.orientation = snapshot.quaternion
            entity.scale = snapshot.scale
            entity.name = item.id.uuidString
            entity.components.set(CollisionComponent(shapes: [.generateBox(size: [0.12, 0.18, 0.012])]))
            shelfEntity.addChild(entity)
            itemEntities[item.id] = entity

            if installGestures, let arView {
                arView.installGestures([.translation, .rotation, .scale], for: entity)
            }
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
    static func makeShelf(template: ShelfTemplate) -> ModelEntity {
        let root = ModelEntity()
        root.components.set(CollisionComponent(shapes: [.generateBox(size: [0.82, 0.28, 0.2])]))

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
        let normalizedImage = image.normalizedForRendering()
        let height: Float = 0.10
        let aspectRatio = Float(normalizedImage.size.width / max(normalizedImage.size.height, 1))
        let width = max(height * aspectRatio, 0.06)
        let depth: Float = 0.015
        let mesh = MeshResource.generateBox(width: width, height: height, depth: depth)

        let material = textureMaterial(from: normalizedImage)
        return ModelEntity(mesh: mesh, materials: [material])
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

#Preview {
    if let container = try? ModelContainer(
        for: Shelf.self,
        PlacedItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ARShelfRealityView(
            viewModel: ARShelfViewModel(shelf: Shelf(name: "Preview", template: .wood)),
            modelContext: container.mainContext,
            isInterfaceHidden: false,
            onRequestShowInterface: {}
        )
    } else {
        Text("Preview unavailable")
    }
}
