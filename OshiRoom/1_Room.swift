import Foundation
import SwiftData

/// 複数の棚をまとめて管理するAR空間です。
@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var name: String
    var displayOrder: Int = 0
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Shelf.room)
    var shelves: [Shelf]

    init(
        id: UUID = UUID(),
        name: String,
        displayOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        shelves: [Shelf] = []
    ) {
        self.id = id
        self.name = name
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.shelves = shelves
    }
}
