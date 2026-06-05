import RealityKit
import SwiftUI
import UIKit

/// ライト/ダークに応じた非AR空間で3Dモデルをプレビューします。
struct ScannedModelPreviewRealityView: UIViewRepresentable {
    let scannedModel: ScannedModel
    let backgroundColor: UIColor
    let controller: ScannedModelPreviewController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(backgroundColor)

        let anchor = AnchorEntity(world: .zero)
        let entity = makePreviewEntity()
        applyStoredPreviewTransformIfNeeded(to: entity)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        context.coordinator.previewEntity = entity
        context.coordinator.installGestures(on: arView)
        controller.previewEntity = entity
        controller.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        uiView.environment.background = .color(backgroundColor)
        controller.previewEntity = context.coordinator.previewEntity
        controller.arView = uiView
    }

    private func makePreviewEntity() -> Entity {
        if let cachedEntity = ScannedModelPreviewEntityCache.shared.entity(for: scannedModel) {
            return cachedEntity.clone(recursive: true)
        }

        let entity = makePreviewPrototypeEntity()
        ScannedModelPreviewEntityCache.shared.store(entity, for: scannedModel)
        return entity.clone(recursive: true)
    }

    private func makePreviewPrototypeEntity() -> Entity {
        if let modelPath = scannedModel.modelPath,
           let modelURL = ScannedModelStore.url(forRelativePath: modelPath),
           let entity = try? Entity.load(contentsOf: modelURL) {
            entity.scale = previewScale(for: scannedModel.method)
            return entity
        }

        if scannedModel.method == .lidar,
           let captureDirectoryPath = scannedModel.captureDirectoryPath,
           let snapshot = ScannedModelStore.loadLiDARSnapshot(relativePath: captureDirectoryPath),
           let entity = makeLiDARMeshEntity(from: snapshot) {
            return entity
        }

        if scannedModel.method == .trueDepth,
           let captureDirectoryPath = scannedModel.captureDirectoryPath,
           let snapshot = ScannedModelStore.loadTrueDepthSnapshot(relativePath: captureDirectoryPath),
           let entity = makeTrueDepthPointCloudEntity(from: snapshot) {
            return entity
        }

        return placeholderEntity()
    }

    private func applyStoredPreviewTransformIfNeeded(to entity: Entity) {
        let snapshot = scannedModel.previewTransformSnapshot
        if snapshot != .identity {
            entity.position = snapshot.position
            entity.orientation = snapshot.quaternion
            entity.scale = snapshot.scale
            return
        }

        entity.position = [0, 0, -0.24]
    }

    private func previewScale(for method: ScanMethod) -> SIMD3<Float> {
        switch method {
        case .lidar:
            [5.0, 5.0, 5.0]
        case .photogrammetry:
            [5.0, 5.0, 5.0]
        case .objectCapture:
            [5.0, 5.0, 5.0]
        case .trueDepth:
            [6.2, 6.2, 6.2]
        }
    }

    private func makeTrueDepthPointCloudEntity(from snapshot: TrueDepthSnapshot) -> Entity? {
        guard snapshot.isEmpty == false else {
            return nil
        }

        let root = Entity()
        let vectors = snapshot.points.map(\.simdValue)
        let center = vectors.reduce(SIMD3<Float>.zero, +) / Float(vectors.count)
        let pointMaterial = SimpleMaterial(
            color: UIColor(red: 0.10, green: 0.56, blue: 0.42, alpha: 0.86),
            roughness: 0.45,
            isMetallic: false
        )
        let pointMesh = MeshResource.generateSphere(radius: 0.004)

        for vector in vectors {
            let point = ModelEntity(mesh: pointMesh, materials: [pointMaterial])
            point.position = vector - center
            root.addChild(point)
        }

        if let boundingBox = snapshot.boundingBox {
            let box = makeBoundingBoxEntity(boundingBox: boundingBox, center: center)
            root.addChild(box)
        }

        root.scale = [4.5, 4.5, 4.5]
        return root
    }

    private func makeBoundingBoxEntity(boundingBox: TrueDepthBoundingBox, center: SIMD3<Float>) -> Entity {
        let size = SIMD3<Float>(
            max(boundingBox.width, 0.01),
            max(boundingBox.height, 0.01),
            max(boundingBox.depth, 0.01)
        )
        let position = (boundingBox.min.simdValue + boundingBox.max.simdValue) * 0.5 - center
        let material = SimpleMaterial(
            color: UIColor(red: 0.10, green: 0.56, blue: 0.42, alpha: 0.18),
            roughness: 0.5,
            isMetallic: false
        )
        let box = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        box.position = position
        return box
    }

    private func makeLiDARMeshEntity(from snapshot: ScannedMeshSnapshot) -> Entity? {
        guard snapshot.isEmpty == false else {
            return nil
        }

        var positions: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []

        let allVertices = snapshot.anchors.flatMap { $0.vertices.map(\.simdValue) }
        guard allVertices.isEmpty == false else {
            return nil
        }

        let center = allVertices.reduce(SIMD3<Float>.zero, +) / Float(allVertices.count)

        for anchor in snapshot.anchors {
            guard let baseIndex = UInt32(exactly: positions.count) else {
                return nil
            }

            positions.append(contentsOf: anchor.vertices.map { $0.simdValue - center })
            triangleIndices.append(contentsOf: anchor.triangleIndices.map { $0 + baseIndex })
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(triangleIndices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return nil
        }

        let material = SimpleMaterial(
            color: UIColor(red: 0.20, green: 0.48, blue: 0.92, alpha: 0.72),
            roughness: 0.5,
            isMetallic: false
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.scale = [5.0, 5.0, 5.0]
        return entity
    }

    private func placeholderEntity() -> Entity {
        let root = Entity()
        let color: UIColor
        switch scannedModel.method {
        case .lidar:
            color = UIColor(red: 0.20, green: 0.48, blue: 0.92, alpha: 1)
        case .photogrammetry:
            color = UIColor(red: 0.92, green: 0.48, blue: 0.20, alpha: 1)
        case .objectCapture:
            color = UIColor(red: 0.34, green: 0.28, blue: 0.86, alpha: 1)
        case .trueDepth:
            color = UIColor(red: 0.10, green: 0.56, blue: 0.42, alpha: 1)
        }

        let material = SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)
        let main = ModelEntity(mesh: .generateBox(size: [0.22, 0.22, 0.22]), materials: [material])
        root.addChild(main)

        let ringMaterial = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.85), roughness: 0.4, isMetallic: false)
        for index in 0..<8 {
            let angle = Float(index) * (.pi / 4)
            let point = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [ringMaterial])
            point.position = [cos(angle) * 0.18, sin(angle) * 0.08, sin(angle) * 0.18]
            root.addChild(point)
        }

        root.scale = [5.2, 5.2, 5.2]
        return root
    }

    final class Coordinator: NSObject {
        weak var previewEntity: Entity?
        private var baseScale: SIMD3<Float> = .one
        private var baseRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        private var basePosition = SIMD3<Float>(0, 0, -0.24)

        func installGestures(on arView: ARView) {
            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

            pinchGesture.delegate = self
            rotationGesture.delegate = self
            panGesture.delegate = self

            arView.addGestureRecognizer(pinchGesture)
            arView.addGestureRecognizer(rotationGesture)
            arView.addGestureRecognizer(panGesture)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseScale = previewEntity.scale
            case .changed:
                let scaleFactor = Float(gesture.scale)
                let nextScale = clampScale(baseScale * scaleFactor)
                previewEntity.scale = nextScale
            default:
                baseScale = previewEntity.scale
            }
        }

        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let previewEntity else {
                return
            }

            switch gesture.state {
            case .began:
                baseRotation = previewEntity.orientation
            case .changed:
                let deltaRotation = simd_quatf(angle: -Float(gesture.rotation), axis: [0, 1, 0])
                previewEntity.orientation = deltaRotation * baseRotation
            default:
                baseRotation = previewEntity.orientation
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let previewEntity, let view = gesture.view else {
                return
            }

            switch gesture.state {
            case .began:
                basePosition = previewEntity.position
            case .changed:
                let translation = gesture.translation(in: view)
                previewEntity.position = [
                    basePosition.x + Float(translation.x) * 0.0012,
                    basePosition.y - Float(translation.y) * 0.0012,
                    basePosition.z
                ]
            default:
                basePosition = previewEntity.position
            }
        }

        private func clampScale(_ scale: SIMD3<Float>) -> SIMD3<Float> {
            let minScale: Float = 0.15
            let maxScale: Float = 18.0
            return [
                min(max(scale.x, minScale), maxScale),
                min(max(scale.y, minScale), maxScale),
                min(max(scale.z, minScale), maxScale)
            ]
        }
    }
}

private final class ScannedModelPreviewEntityCache {
    static let shared = ScannedModelPreviewEntityCache()

    private let storage = NSCache<NSString, EntityBox>()

    private init() {
        storage.countLimit = 4
    }

    func entity(for model: ScannedModel) -> Entity? {
        storage.object(forKey: cacheKey(for: model))?.entity
    }

    func store(_ entity: Entity, for model: ScannedModel) {
        storage.setObject(EntityBox(entity: entity), forKey: cacheKey(for: model))
    }

    private func cacheKey(for model: ScannedModel) -> NSString {
        NSString(string: model.id.uuidString)
    }
}

private final class EntityBox {
    let entity: Entity

    init(entity: Entity) {
        self.entity = entity
    }
}

final class ScannedModelPreviewController {
    weak var arView: ARView?
    weak var previewEntity: Entity?

    func snapshotCurrentImage() -> UIImage? {
        guard let arView, arView.bounds.isEmpty == false else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: arView.bounds.size, format: format)
        return renderer.image { _ in
            arView.drawHierarchy(in: arView.bounds, afterScreenUpdates: true)
        }
    }

    func snapshotCurrentTransform() -> TransformSnapshot? {
        guard let previewEntity else {
            return nil
        }

        return TransformSnapshot(
            position: previewEntity.position,
            rotation: previewEntity.orientation,
            scale: previewEntity.scale
        )
    }
}

extension ScannedModelPreviewRealityView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
