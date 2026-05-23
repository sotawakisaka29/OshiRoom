import SwiftData
import SwiftUI

@main
struct OshiRoomApp: App {
    private let modelContainer: ModelContainer = {
        let modelTypes: [any PersistentModel.Type] = [Shelf.self, PlacedItem.self, ScannedModel.self]
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // SwiftDataの移行失敗などで起動不能になるより、まずアプリを開けることを優先します。
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let fallbackContainer = try? ModelContainer(for: schema, configurations: [fallbackConfiguration]) else {
                fatalError("SwiftDataのModelContainerを作成できませんでした: \(error.localizedDescription)")
            }
            return fallbackContainer
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
