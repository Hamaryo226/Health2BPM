import SwiftUI

@main
struct Health2BPMWatchApp: App {
    @StateObject private var heartRateManager = HeartRateManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(heartRateManager)
        }
    }
}
