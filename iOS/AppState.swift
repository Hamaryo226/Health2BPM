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
    @Published var isPlaying = false

    let spotify = SpotifyService()
    private let watchSession = WatchSessionManager()
    @Published var isAuthenticating = false
    @Published var isSpotifyConnected = false
    private var savedClientID = ""
    private var savedRedirectURI = ""

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
        spotify.onConnectionChanged = { [weak self] connected in
            self?.isSpotifyConnected = connected
            if !connected { self?.tracks = [] }
        }
        spotify.onLoginError = { [weak self] error in
            self?.isAuthenticating = false
            self?.statusMessage = error.localizedDescription
        }
        savedClientID = clientID
        savedRedirectURI = redirectURI
        do {
            try spotify.restore(clientID: clientID, redirectURI: redirectURI)
        } catch {
            statusMessage = error.localizedDescription
        }
        watchSession.activate()
    }

    var currentTrack: RecommendedTrack? {
        guard tracks.indices.contains(currentTrackIndex) else { return nil }
        return tracks[currentTrackIndex]
    }

    var canGoBack: Bool { currentTrackIndex > 0 && currentTrack != nil }
    var canGoForward: Bool { currentTrackIndex + 1 < tracks.count }

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
        guard !isAuthenticating, !isLoading, !isPlaying else { return }
        guard saveSpotifySettings() else { return }
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Spotify Client IDを入力してください"
            return
        }
        guard URLComponents(string: redirectURI)?.scheme == "health2bpm" else {
            statusMessage = "Redirect URIは health2bpm:// で始めてください"
            return
        }
        statusMessage = "Spotifyで認証してください"
        do {
            try spotify.startLogin(clientID: clientID, redirectURI: redirectURI)
            isAuthenticating = true
        } catch {
            isAuthenticating = false
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveSpotifySettings() -> Bool {
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        market = market.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        redirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if market.isEmpty {
            market = "JP"
        }
        if redirectURI.isEmpty {
            redirectURI = "health2bpm://spotify-callback"
        }
        if clientID != savedClientID || redirectURI != savedRedirectURI {
            do { try spotify.disconnect() } catch {
                isAuthenticating = false
                statusMessage = error.localizedDescription
                return false
            }
            isAuthenticating = false
            tracks = []
        }
        savedClientID = clientID
        savedRedirectURI = redirectURI
        UserDefaults.standard.set(clientID, forKey: "spotifyClientID")
        UserDefaults.standard.set(market, forKey: "spotifyMarket")
        UserDefaults.standard.set(redirectURI, forKey: "spotifyRedirectURI")
        statusMessage = "Spotify API設定を保存しました"
        return true
    }

    func disconnectSpotify() {
        do {
            try spotify.disconnect()
            isAuthenticating = false
            tracks = []
            currentTrackIndex = 0
            statusMessage = "Spotifyの接続を解除しました"
        } catch {
            isAuthenticating = false
            statusMessage = error.localizedDescription
        }
    }

    func handleSpotifyCallback(_ url: URL) {
        Task {
            do {
                guard try await spotify.finishLogin(callbackURL: url) else { return }
                isAuthenticating = false
                statusMessage = "Spotifyに接続しました"
                if selectedMood != nil, latestBPM != nil { await fetchTracks() }
            } catch is CancellationError {
                // A disconnect or new login superseded this request.
            } catch {
                spotify.cancelLogin()
                isAuthenticating = false
                statusMessage = "Spotify認証に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func fetchTracks() async {
        guard !isLoading, !isAuthenticating else { return }
        guard clientID == savedClientID, redirectURI == savedRedirectURI else {
            statusMessage = "変更したSpotify設定を保存し、再接続してください"
            return
        }
        guard let mood = selectedMood, let bpm = latestBPM else {
            statusMessage = "ムードを選び、Apple Watchで心拍数を取得してください"
            return
        }
        let requestedMarket = market
        isLoading = true
        tracks = []
        currentTrackIndex = 0
        statusMessage = "楽曲を取得しています"
        step = .suggestions
        defer { isLoading = false }

        do {
            let fetchedTracks = try await spotify.recommendations(mood: mood, bpm: bpm, market: requestedMarket)
            guard selectedMood == mood, market == requestedMarket else {
                statusMessage = "検索条件が変わりました。もう一度曲を取得してください"
                return
            }
            tracks = fetchedTracks
            currentTrackIndex = 0
            step = .suggestions
            statusMessage = tracks.isEmpty
                ? "条件に合う曲が見つかりませんでした。ムードを変えて再取得してください"
                : "\(tracks.count)曲を提案しました（\(mood.title)・\(bpm) BPM）"
        } catch is CancellationError {
            return
        } catch {
            statusMessage = "楽曲取得に失敗しました: \(error.localizedDescription)"
        }
    }

    func playCurrentTrack() {
        guard !isPlaying, let currentTrack else { return }
        isPlaying = true
        Task {
            defer { isPlaying = false }
            do {
                try await spotify.play(trackURI: currentTrack.uri)
                statusMessage = "Spotifyで再生を開始しました"
            } catch is CancellationError {
                return
            } catch let error as SpotifyHTTPError where error.status != 404 {
                statusMessage = error.localizedDescription
            } catch let error as SpotifyError {
                statusMessage = error.localizedDescription
            } catch {
                let opened = await UIApplication.shared.open(currentTrack.spotifyURL)
                statusMessage = opened
                    ? "曲のリンクを開きました。Spotifyで再生してください"
                    : "曲を開けませんでした。Spotifyのインストールと通信状態を確認してください"
            }
        }
    }

    func previousTrack() {
        guard canGoBack else { return }
        currentTrackIndex -= 1
    }

    func skipTrack() {
        if currentTrackIndex < tracks.count - 1 {
            currentTrackIndex += 1
        } else {
            statusMessage = "\(tracks.count)曲すべて確認しました"
        }
    }
}
