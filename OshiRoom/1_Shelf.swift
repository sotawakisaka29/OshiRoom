import Foundation
import SwiftData

/// ユーザーが作成したAR棚です。
@Model
final class Shelf {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateRawValue: String
    var thumbnailData: Data?
    var createdAt: Date
    var updatedAt: Date
    var anchorTransformData: Data?

    @Relationship(deleteRule: .cascade, inverse: \PlacedItem.shelf)
    var items: [PlacedItem]

    init(
        id: UUID = UUID(),
        name: String,
        template: ShelfTemplate,
        thumbnailData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        anchorTransformData: Data? = nil,
        items: [PlacedItem] = []
    ) {
        self.id = id
        self.name = name
        self.templateRawValue = template.rawValue
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.anchorTransformData = anchorTransformData
        self.items = items
    }

    var template: ShelfTemplate {
        get { ShelfTemplate(rawValue: templateRawValue) ?? .wood }
        set { templateRawValue = newValue.rawValue }
    }
}
