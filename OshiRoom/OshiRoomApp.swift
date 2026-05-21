import SwiftData
import SwiftUI

@main
struct OshiRoomApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Shelf.self, PlacedItem.self])
    }
}
