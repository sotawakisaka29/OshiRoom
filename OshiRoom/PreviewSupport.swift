import SwiftData

/// Preview用のインメモリSwiftDataコンテナを作ります。
enum PreviewModelContainer {
    @MainActor
    static func make() -> ModelContainer {
        let schema = Schema([Shelf.self, PlacedItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let shelf = Shelf(name: "ライブ記念棚", template: .wood)
            container.mainContext.insert(shelf)
            return container
        } catch {
            let fallbackSchema = Schema([Shelf.self, PlacedItem.self])
            let fallbackConfiguration = ModelConfiguration(schema: fallbackSchema, isStoredInMemoryOnly: true)
            guard let fallback = try? ModelContainer(for: fallbackSchema, configurations: [fallbackConfiguration]) else {
                fatalError("Preview用のModelContainerを作成できませんでした。")
            }
            return fallback
        }
    }
}
