import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Step {
        case mood
        case heartRate
        case spotify
        case suggestions
    }

    @Published var step: Step = .mood
    @Published var selectedMood: Mood?
    @Published var latestBPM: Int?
    @Published var clientID = ""
    @Published var market = "JP"
    @Published var redirectURI = "health2bpm://spotify-callback"
    @Published var statusMessage = "Apple Watchで心拍数を測定してください"
    @Published var tracks: [RecommendedTrack] = []
    @Published var currentTrackIndex = 0
    @Published var isLoading = false

    let spotify = SpotifyService()
    private let watchSession = WatchSessionManager()
    private var handledSpotifyCallbacks = Set<String>()

    init() {
        clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        market = UserDefaults.standard.string(forKey: "spotifyMarket") ?? "JP"
        redirectURI = UserDefaults.standard.string(forKey: "spotifyRedirectURI") ?? "health2bpm://spotify-callback"
        watchSession.onHeartRate = { [weak self] bpm in
            Task { @MainActor in
                self?.latestBPM = bpm
                self?.statusMessage = "Apple Watchから \(bpm) BPM を受信しました"
            }
        }
        spotify.onCallbackURL = { [weak self] url in
            Task { @MainActor in
                self?.handleSpotifyCallback(url)
            }
        }
        watchSession.activate()
    }

    var currentTrack: RecommendedTrack? {
        guard tracks.indices.contains(currentTrackIndex) else { return nil }
        return tracks[currentTrackIndex]
    }

    func selectMood(_ mood: Mood) {
        selectedMood = mood
        step = .heartRate
    }

    func continueToSpotify() {
        guard latestBPM != nil else {
            statusMessage = "先にApple Watchで心拍数を取得してください"
            return
        }
        step = .spotify
    }

    func loginToSpotify() {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Spotify Client IDを入力してください"
            return
        }
        guard URLComponents(string: redirectURI)?.scheme == "health2bpm" else {
            statusMessage = "Redirect URIは health2bpm:// で始めてください"
            return
        }
        saveSpotifySettings()
        statusMessage = "Spotifyで認証してください"
        spotify.startLogin(clientID: clientID, redirectURI: redirectURI)
    }

    func saveSpotifySettings() {
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        market = market.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        redirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if market.isEmpty {
            market = "JP"
        }
        if redirectURI.isEmpty {
            redirectURI = "health2bpm://spotify-callback"
        }
        UserDefaults.standard.set(clientID, forKey: "spotifyClientID")
        UserDefaults.standard.set(market, forKey: "spotifyMarket")
        UserDefaults.standard.set(redirectURI, forKey: "spotifyRedirectURI")
        statusMessage = "Spotify API設定を保存しました"
    }

    func handleSpotifyCallback(_ url: URL) {
        guard handledSpotifyCallbacks.insert(url.absoluteString).inserted else { return }
        Task {
            do {
                try await spotify.finishLogin(callbackURL: url, clientID: clientID, redirectURI: redirectURI)
                statusMessage = "Spotifyに接続しました"
                await fetchTracks()
            } catch {
                statusMessage = "Spotify認証に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func fetchTracks() async {
        guard let mood = selectedMood, let bpm = latestBPM else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            tracks = try await spotify.recommendations(mood: mood, bpm: bpm, market: market)
            currentTrackIndex = 0
            step = .suggestions
            statusMessage = "\(tracks.count)曲を提案しました"
        } catch {
            statusMessage = "楽曲取得に失敗しました: \(error.localizedDescription)"
        }
    }

    func playCurrentTrack() {
        guard let currentTrack else { return }
        Task {
            do {
                try await spotify.play(trackURI: currentTrack.uri)
                statusMessage = "Spotifyで再生を開始しました"
            } catch {
                await UIApplication.shared.open(currentTrack.spotifyURL)
                statusMessage = "Spotifyアプリで開きました"
            }
        }
    }

    func skipTrack() {
        if currentTrackIndex < tracks.count - 1 {
            currentTrackIndex += 1
        } else {
            statusMessage = "10曲すべて確認しました"
        }
    }
}
