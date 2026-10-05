import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BuilderView()
                .tabItem { Label("Create", systemImage: "qrcode") }
            LibraryView()
                .tabItem { Label("My Codes", systemImage: "square.grid.2x2") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StoreManager())
        .environmentObject(CodeLibrary())
}
