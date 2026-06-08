import Foundation
import SwiftData
import SwiftUI

@main
struct OshiRoomApp: App {
    private let modelContainer: ModelContainer = {
        let modelTypes: [any PersistentModel.Type] = [Room.self, Shelf.self, PlacedItem.self, ScannedModel.self]
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            migrateLegacyShelvesIfNeeded(in: container.mainContext)
            repairRoomDisplayOrderIfNeeded(in: container.mainContext)
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
            if isPromotionMode {
                PromotionLaunchView()
            } else {
                ContentView()
            }
        }
        .modelContainer(modelContainer)
    }

    private var isPromotionMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--promotion")
    }

    private static func migrateLegacyShelvesIfNeeded(in modelContext: ModelContext) {
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

        let legacyShelves = shelves.filter { $0.room == nil }

        guard legacyShelves.isEmpty == false else {
            return
        }

        let currentMaxRoomOrder = ((try? modelContext.fetch(FetchDescriptor<Room>(
            sortBy: [SortDescriptor(\Room.displayOrder, order: .reverse)]
        ))) ?? []).first?.displayOrder ?? -1

        var nextRoomOrder = currentMaxRoomOrder + 1
        for shelf in legacyShelves {
            let room = Room(
                name: shelf.name,
                displayOrder: nextRoomOrder,
                createdAt: shelf.createdAt,
                updatedAt: shelf.updatedAt
            )
            nextRoomOrder += 1
            room.shelves.append(shelf)
            shelf.room = room
            modelContext.insert(room)
        }

        try? modelContext.save()
    }

    private static func repairRoomDisplayOrderIfNeeded(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Room>(
            sortBy: [
                SortDescriptor(\Room.displayOrder, order: .forward),
                SortDescriptor(\Room.updatedAt, order: .reverse)
            ]
        )

        guard let rooms = try? modelContext.fetch(descriptor),
              rooms.isEmpty == false else {
            return
        }

        let needsRepair = rooms.enumerated().contains { index, room in
            room.displayOrder != index
        }

        guard needsRepair else {
            return
        }

        for (index, room) in rooms.enumerated() {
            room.displayOrder = index
        }

        try? modelContext.save()
    }
}
