import SwiftData
import SwiftUI

/// アプリ全体の入口になる画面です。
struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewModelContainer.make())
}
