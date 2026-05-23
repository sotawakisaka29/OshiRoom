import Foundation
import simd

/// LiDARで取得したARMeshAnchorを軽量JSONとして保存するための形です。
struct ScannedMeshSnapshot: Codable {
    var anchors: [ScannedMeshAnchorSnapshot]

    var isEmpty: Bool {
        anchors.allSatisfy { $0.vertices.isEmpty || $0.triangleIndices.isEmpty }
    }
}

struct ScannedMeshAnchorSnapshot: Codable {
    var vertices: [ScannedMeshVertex]
    var triangleIndices: [UInt32]
}

struct ScannedMeshVertex: Codable {
    var x: Float
    var y: Float
    var z: Float

    init(_ vector: SIMD3<Float>) {
        x = vector.x
        y = vector.y
        z = vector.z
    }

    var simdValue: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
