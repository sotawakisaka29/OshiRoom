import SwiftData
import SwiftUI

@main
struct OshiRoomApp: App {
    private let modelContainer: ModelContainer = {
        let modelTypes: [any PersistentModel.Type] = [Shelf.self, PlacedItem.self, ScannedModel.self]
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            repairShelfDisplayOrderIfNeeded(in: container.mainContext)
            return container
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

    private static func repairShelfDisplayOrderIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Shelf>(
            sortBy: [
                SortDescriptor(\Shelf.displayOrder, order: .forward),
                SortDescriptor(\Shelf.updatedAt, order: .reverse)
            ]
        )

        guard let shelves = try? modelContext.fetch(descriptor),
              shelves.isEmpty == false else {
            return
        }

        let needsRepair = shelves.enumerated().contains { index, shelf in
            shelf.displayOrder != index
        }

        guard needsRepair else {
            return
        }

        for (index, shelf) in shelves.enumerated() {
            shelf.displayOrder = index
        }

        try? modelContext.save()
    }
}
