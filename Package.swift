// swift-tools-version: 5.9
import PackageDescription

// Isolated iOS authentication tests. The app continues to use Health2BPM.xcodeproj.
let package = Package(
    name: "Health2BPMAuth",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Health2BPMAuth", targets: ["Health2BPMAuth"])],
    targets: [
        .target(name: "Health2BPMAuth", path: ".",
                exclude: ["Watch", "Tests", "Health2BPM.xcodeproj", "README.md", "project.yml",
                          "iOS/AppState.swift", "iOS/ContentView.swift", "iOS/Health2BPMApp.swift",
                          "iOS/WatchSessionManager.swift", "iOS/Info.plist", "iOS/Health2BPM.entitlements"],
                sources: ["iOS/SpotifyService.swift", "Shared"]),
        .testTarget(name: "SpotifyAuthTests", dependencies: ["Health2BPMAuth"], path: "Tests/SpotifyAuthTests"),
    ]
)
