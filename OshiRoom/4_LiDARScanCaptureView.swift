import ARKit
import RealityKit
import SwiftUI

/// LiDAR方式の試験用キャプチャ画面です。
struct LiDARScanCaptureView: UIViewRepresentable {
    let onScanUpdated: (Int, ScannedMeshSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanUpdated: onScanUpdated)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        arView.automaticallyConfigureSession = false
        arView.debugOptions = [.showSceneUnderstanding]

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        arView.session.run(configuration)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject, ARSessionDelegate {
        private let onScanUpdated: (Int, ScannedMeshSnapshot) -> Void
        private var meshSnapshots: [UUID: ScannedMeshAnchorSnapshot] = [:]

        init(onScanUpdated: @escaping (Int, ScannedMeshSnapshot) -> Void) {
            self.onScanUpdated = onScanUpdated
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            guard meshAnchors.isEmpty == false else {
                return
            }

            for meshAnchor in meshAnchors {
                meshSnapshots[meshAnchor.identifier] = makeSnapshot(from: meshAnchor)
            }

            let snapshot = ScannedMeshSnapshot(anchors: Array(meshSnapshots.values))
            DispatchQueue.main.async {
                self.onScanUpdated(meshAnchors.count, snapshot)
            }
        }

        private func makeSnapshot(from meshAnchor: ARMeshAnchor) -> ScannedMeshAnchorSnapshot {
            let geometry = meshAnchor.geometry
            let vertices = (0..<geometry.vertices.count).map { index in
                let localVertex = geometry.vertex(at: index)
                let worldVertex = meshAnchor.transform * SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
                return ScannedMeshVertex(SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z))
            }

            var triangleIndices: [UInt32] = []
            triangleIndices.reserveCapacity(geometry.faces.count * geometry.faces.indexCountPerPrimitive)

            for faceIndex in 0..<geometry.faces.count {
                triangleIndices.append(contentsOf: geometry.faceIndices(at: faceIndex))
            }

            return ScannedMeshAnchorSnapshot(vertices: vertices, triangleIndices: triangleIndices)
        }
    }
}

private extension ARMeshGeometry {
    func vertex(at index: Int) -> SIMD3<Float> {
        let offset = vertices.offset + vertices.stride * index
        let pointer = vertices.buffer.contents().advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self)
        return pointer.pointee
    }

    func faceIndices(at index: Int) -> [UInt32] {
        let indexCount = faces.indexCountPerPrimitive
        let offset = index * indexCount * faces.bytesPerIndex
        let pointer = faces.buffer.contents().advanced(by: offset)

        if faces.bytesPerIndex == MemoryLayout<UInt16>.size {
            let typedPointer = pointer.assumingMemoryBound(to: UInt16.self)
            return (0..<indexCount).map { UInt32(typedPointer[$0]) }
        }

        let typedPointer = pointer.assumingMemoryBound(to: UInt32.self)
        return (0..<indexCount).map { typedPointer[$0] }
    }
}
