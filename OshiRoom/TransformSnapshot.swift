import Foundation
import simd

/// RealityKitのTransformをSwiftDataへ保存しやすい形にした値です。
struct TransformSnapshot: Codable, Equatable {
    var position: SIMD3<Float>
    var rotation: SIMD4<Float>
    var scale: SIMD3<Float>

    init(
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
        scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    ) {
        self.position = position
        self.rotation = [rotation.vector.x, rotation.vector.y, rotation.vector.z, rotation.vector.w]
        self.scale = scale
    }

    var quaternion: simd_quatf {
        simd_quatf(vector: rotation)
    }

    static var identity: TransformSnapshot {
        TransformSnapshot()
    }
}

/// ARアンカーの4x4行列をDataとして保存するための変換をまとめます。
enum MatrixCoder {
    static func encode(_ matrix: simd_float4x4) -> Data? {
        let values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
        return try? JSONEncoder().encode(values)
    }

    static func decode(_ data: Data?) -> simd_float4x4? {
        guard let data, let values = try? JSONDecoder().decode([Float].self, from: data), values.count == 16 else {
            return nil
        }

        return simd_float4x4(
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        )
    }
}
