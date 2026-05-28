import SwiftData
import SwiftUI

/// アプリ全体の入口になる画面です。
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }

            EncyclopediaView()
                .tabItem {
                    Label("図鑑", systemImage: "square.grid.2x2.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewModelContainer.make())
}
