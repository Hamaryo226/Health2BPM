import SwiftUI

@main
struct Health2BPMApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.handleSpotifyCallback(url)
                }
        }
    }
}
