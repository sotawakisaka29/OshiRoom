import Foundation
import simd

/// 前面TrueDepthカメラから作る、スケール補正用の簡易点群です。
struct TrueDepthSnapshot: Codable {
    var points: [ScannedMeshVertex]
    var boundingBox: TrueDepthBoundingBox?
    var capturedAt: Date

    var isEmpty: Bool {
        points.isEmpty
    }
}

struct TrueDepthBoundingBox: Codable {
    var min: ScannedMeshVertex
    var max: ScannedMeshVertex

    var width: Float {
        max.x - min.x
    }

    var height: Float {
        max.y - min.y
    }

    var depth: Float {
        max.z - min.z
    }

    var sizeText: String {
        let widthCentimeters = Int((width * 100).rounded())
        let heightCentimeters = Int((height * 100).rounded())
        let depthCentimeters = Int((depth * 100).rounded())
        return "\(widthCentimeters)cm × \(heightCentimeters)cm × \(depthCentimeters)cm"
    }
}
