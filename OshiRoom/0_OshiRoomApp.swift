import Foundation
import SwiftData
import UIKit
import SwiftUI

@main
struct OshiRoomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }

    fileprivate static func makeModelContainer() -> ModelContainer {
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLockController.supportedInterfaceOrientations
    }
}

enum OrientationLockController {
    private static var isPortraitOnly = false

    static var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if isPortraitOnly {
            return .portrait
        }

        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    static func setPortraitOnly(_ enabled: Bool) {
        guard isPortraitOnly != enabled else {
            return
        }

        isPortraitOnly = enabled
        applyCurrentOrientationPreferences()
    }

    static func applyCurrentOrientationPreferences() {
        guard #available(iOS 16.0, *) else {
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: supportedInterfaceOrientations
        )

        try? scene.requestGeometryUpdate(preferences)
    }
}

private struct AppRootView: View {
    @State private var modelContainer = OshiRoomApp.makeModelContainer()

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--promotion") {
                PromotionLaunchView()
            } else {
                ContentView()
            }
        }
        .modelContainer(modelContainer)
    }
}
