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
    @Published var isSavingFavorite = false
    @Published var favoriteURIs: Set<String> = []
    @Published var isSavingPlaylist = false
    @Published var playlistMessage = ""
    @Published var createdPlaylist: SpotifyCreatedPlaylist?
    @Published var playlistSaved = false
    private var playlistURIs: [String] = []

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
            if !connected {
                self?.tracks = []
                self?.favoriteURIs = []
                self?.createdPlaylist = nil
                self?.playlistURIs = []
                self?.playlistSaved = false
                self?.playlistMessage = ""
            }
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
        guard !isAuthenticating, !isLoading, !isPlaying, !isSavingFavorite, !isSavingPlaylist else { return }
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

    func saveCurrentFavorite() async {
        guard !isSavingFavorite, !isAuthenticating, isSpotifyConnected, let track = currentTrack else { return }
        isSavingFavorite = true
        defer { isSavingFavorite = false }
        do {
            try await spotify.saveFavorite(trackURI: track.uri)
            favoriteURIs.insert(track.uri)
            statusMessage = "「\(track.name)」をSpotifyのお気に入りに追加しました"
        } catch is CancellationError {
            return
        } catch {
            statusMessage = saveErrorMessage(error)
        }
    }

    func beginPlaylist() {
        guard !isSavingPlaylist else { return }
        // Keep an unfinished save so retry does not create another playlist.
        if createdPlaylist != nil && !playlistSaved { return }
        createdPlaylist = nil
        playlistSaved = false
        playlistMessage = ""
        var seen: Set<String> = []
        playlistURIs = tracks.map(\.uri).filter { seen.insert($0).inserted }
    }

    var playlistTrackCount: Int { playlistURIs.count }

    func savePlaylist(name: String) async {
        guard !isSavingPlaylist, !playlistSaved, !isAuthenticating, isSpotifyConnected else { return }
        guard !playlistURIs.isEmpty, playlistURIs.count <= 100 else {
            playlistMessage = "保存する曲がありません。提案曲を取得してください"
            return
        }
        isSavingPlaylist = true
        defer { isSavingPlaylist = false }
        do {
            if createdPlaylist == nil {
                createdPlaylist = try await spotify.createPlaylist(name: name)
            }
            guard let playlist = createdPlaylist else { return }
            try await spotify.savePlaylistTracks(playlistID: playlist.id, uris: playlistURIs)
            playlistSaved = true
            playlistMessage = "\(playlistURIs.count)曲を非公開プレイリストに保存しました"
            statusMessage = playlistMessage
        } catch is CancellationError {
            return
        } catch {
            let prefix = createdPlaylist == nil
                ? "作成を確認できませんでした。通信エラーの場合はSpotifyに同名のリストがないか確認してください。"
                : "プレイリストは作成済みですが、曲の保存を確認できませんでした。同じリストへ再試行できます。"
            playlistMessage = prefix + "\n" + saveErrorMessage(error)
        }
    }

    private func saveErrorMessage(_ error: Error) -> String {
        if let http = error as? SpotifyHTTPError, http.status == 403 {
            return "保存権限を確認してください。Spotifyに再接続して追加権限を許可してください（HTTP 403）"
        }
        return error.localizedDescription
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
