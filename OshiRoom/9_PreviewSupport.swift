import SwiftData

/// Preview用のインメモリSwiftDataコンテナを作ります。
enum PreviewModelContainer {
    @MainActor
    static func make() -> ModelContainer {
        let modelTypes: [any PersistentModel.Type] = [Room.self, Shelf.self, PlacedItem.self, ScannedModel.self]
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let room = Room(name: "ライブ記念ルーム")
            let shelf = Shelf(name: "メイン棚", template: .wood, room: room)
            room.shelves.append(shelf)
            container.mainContext.insert(room)
            container.mainContext.insert(shelf)
            return container
        } catch {
            let fallbackSchema = Schema(modelTypes)
            let fallbackConfiguration = ModelConfiguration(schema: fallbackSchema, isStoredInMemoryOnly: true)
            guard let fallback = try? ModelContainer(for: fallbackSchema, configurations: [fallbackConfiguration]) else {
                fatalError("Preview用のModelContainerを作成できませんでした。")
            }
            return fallback
        }
    }
}
