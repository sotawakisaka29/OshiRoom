import Foundation
import SwiftData
import simd

/// 棚の上に配置された疑似3Dグッズです。
@Model
final class PlacedItem {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var positionX: Float
    var positionY: Float
    var positionZ: Float
    var rotationX: Float
    var rotationY: Float
    var rotationZ: Float
    var rotationW: Float
    var scaleX: Float
    var scaleY: Float
    var scaleZ: Float
    var slotIndex: Int
    var createdAt: Date
    var shelf: Shelf?

    init(
        id: UUID = UUID(),
        imagePath: String,
        transform: TransformSnapshot = .identity,
        slotIndex: Int,
        createdAt: Date = .now,
        shelf: Shelf? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.positionX = transform.position.x
        self.positionY = transform.position.y
        self.positionZ = transform.position.z
        self.rotationX = transform.rotation.x
        self.rotationY = transform.rotation.y
        self.rotationZ = transform.rotation.z
        self.rotationW = transform.rotation.w
        self.scaleX = transform.scale.x
        self.scaleY = transform.scale.y
        self.scaleZ = transform.scale.z
        self.slotIndex = slotIndex
        self.createdAt = createdAt
        self.shelf = shelf
    }

    var transformSnapshot: TransformSnapshot {
        get {
            TransformSnapshot(
                position: [positionX, positionY, positionZ],
                rotation: simd_quatf(vector: [rotationX, rotationY, rotationZ, rotationW]),
                scale: [scaleX, scaleY, scaleZ]
            )
        }
        set {
            positionX = newValue.position.x
            positionY = newValue.position.y
            positionZ = newValue.position.z
            rotationX = newValue.rotation.x
            rotationY = newValue.rotation.y
            rotationZ = newValue.rotation.z
            rotationW = newValue.rotation.w
            scaleX = newValue.scale.x
            scaleY = newValue.scale.y
            scaleZ = newValue.scale.z
        }
    }
}
