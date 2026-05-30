import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class SpotifyService: NSObject {
    private let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let apiBaseURL = URL(string: "https://api.spotify.com/v1")!
    private var codeVerifier = ""
    private var webSession: ASWebAuthenticationSession?
    private var accessToken: String?
    var onCallbackURL: ((URL) -> Void)?

    func startLogin(clientID: String, redirectURI: String) {
        guard let callbackScheme = URLComponents(string: redirectURI)?.scheme else {
            print("Invalid redirect URI: \(redirectURI)")
            return
        }

        codeVerifier = Self.randomString(length: 64)
        let challenge = Self.codeChallenge(for: codeVerifier)
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state streaming"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: callbackScheme) { callbackURL, error in
            if let callbackURL {
                Task { @MainActor in
                    self.onCallbackURL?(callbackURL)
                }
            } else if let error {
                print("Spotify login cancelled or failed: \(error.localizedDescription)")
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        session.start()
    }

    func finishLogin(callbackURL: URL, clientID: String, redirectURI: String) async throws {
        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyError.missingAuthorizationCode
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ])

        let token: SpotifyTokenResponse = try await decoded(request)
        accessToken = token.accessToken
    }

    func recommendations(mood: Mood, bpm: Int, market: String) async throws -> [RecommendedTrack] {
        let seed = try await seedTrackID(query: mood.seedQuery, market: market)
        var items = [
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "seed_tracks", value: seed),
            URLQueryItem(name: "target_tempo", value: String(bpm)),
            URLQueryItem(name: "min_tempo", value: String(max(45, bpm - 6))),
            URLQueryItem(name: "max_tempo", value: String(min(210, bpm + 6))),
        ]
        items.append(contentsOf: mood.spotifyTuning.map { URLQueryItem(name: $0.key, value: $0.value) })

        let response: SpotifyRecommendationResponse = try await get("/recommendations", queryItems: items)
        return response.tracks.compactMap(\.recommendedTrack)
    }

    func play(trackURI: String) async throws {
        guard let accessToken else { throw SpotifyError.notAuthenticated }
        var request = URLRequest(url: apiURL(path: "/me/player/play"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["uris": [trackURI]])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyError.playbackUnavailable
        }
    }

    private func seedTrackID(query: String, market: String) async throws -> String {
        let response: SpotifySearchResponse = try await get("/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "limit", value: "1"),
        ])
        guard let id = response.tracks.items.first?.id else { throw SpotifyError.seedTrackNotFound }
        return id
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        guard let accessToken else { throw SpotifyError.notAuthenticated }
        var components = URLComponents(url: apiURL(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await decoded(request)
    }

    private func apiURL(path: String) -> URL {
        path.split(separator: "/").reduce(apiBaseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private func decoded<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func formBody(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let body = values.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func randomString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in characters.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

enum SpotifyError: LocalizedError {
    case missingAuthorizationCode
    case notAuthenticated
    case requestFailed
    case seedTrackNotFound
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAuthorizationCode: "認証コードが見つかりません"
        case .notAuthenticated: "Spotifyにログインしていません"
        case .requestFailed: "Spotify APIリクエストに失敗しました"
        case .seedTrackNotFound: "ムードに合うシード曲が見つかりません"
        case .playbackUnavailable: "Spotify再生デバイスが見つかりません"
        }
    }
}
