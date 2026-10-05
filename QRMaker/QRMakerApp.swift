import SwiftUI

@main
struct QRMakerApp: App {
    @StateObject private var store = StoreManager()
    @StateObject private var library = CodeLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(library)
        }
    }
}
