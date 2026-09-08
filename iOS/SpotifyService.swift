import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class SpotifyService: NSObject {
    private let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let apiBaseURL = URL(string: "https://api.spotify.com/v1")!
    private let session: URLSession
    private let tokenStore: SpotifyTokenStore
    private var credentials: SpotifyCredentials?
    private var pendingLogin: LoginAttempt?
    private var webSession: ASWebAuthenticationSession?
    nonisolated(unsafe) private var presentationWindow: UIWindow?
    private var refreshTask: Task<String, Error>?
    private var generation = UUID()
    var onCallbackURL: ((URL) -> Void)?
    var onLoginError: ((Error) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    var isConnected: Bool { credentials != nil }

    init(session: URLSession = .shared, tokenStore: SpotifyTokenStore = KeychainSpotifyTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
        super.init()
    }

    func restore(clientID: String, redirectURI: String) throws {
        guard let saved = try tokenStore.load() else { return }
        guard saved.clientID == clientID, saved.redirectURI == redirectURI else {
            try tokenStore.delete()
            return
        }
        credentials = saved
        onConnectionChanged?(true)
    }

    func cancelLogin() {
        pendingLogin = nil
        webSession?.cancel()
        webSession = nil
        presentationWindow = nil
    }

    func disconnect() throws {
        generation = UUID()
        pendingLogin = nil
        webSession?.cancel()
        webSession = nil
        presentationWindow = nil
        refreshTask?.cancel()
        refreshTask = nil
        credentials = nil
        onConnectionChanged?(false)
        try tokenStore.delete()
    }

    func startLogin(clientID: String, redirectURI: String) throws {
        guard pendingLogin == nil else { return }
        guard let redirect = URLComponents(string: redirectURI),
              redirect.scheme == "health2bpm", redirect.host != nil,
              redirect.query == nil, redirect.fragment == nil else {
            throw SpotifyError.invalidCallback
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw SpotifyError.loginUnavailable
        }
        let attempt = LoginAttempt(clientID: clientID, redirectURI: redirectURI,
                                   verifier: Self.randomString(length: 64), state: Self.randomString(length: 32))
        pendingLogin = attempt
        presentationWindow = window
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state"),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: attempt.verifier)),
        ]
        let web = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirect.scheme) { [weak self] url, error in
            Task { @MainActor in
                guard let self, self.pendingLogin?.state == attempt.state else { return }
                if let url {
                    self.onCallbackURL?(url)
                } else {
                    self.pendingLogin = nil
                    self.webSession = nil
                    self.presentationWindow = nil
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    self.onLoginError?(cancelled ? SpotifyError.loginCancelled : SpotifyError.loginUnavailable)
                }
            }
        }
        web.presentationContextProvider = self
        webSession = web
        guard web.start() else {
            pendingLogin = nil
            webSession = nil
            presentationWindow = nil
            throw SpotifyError.loginUnavailable
        }
    }

    // Returns false for duplicate or unsolicited callbacks; authorization codes are never retained.
    func finishLogin(callbackURL: URL) async throws -> Bool {
        guard let attempt = pendingLogin else { return false }
        let code = try Self.authorizationCode(from: callbackURL, redirectURI: attempt.redirectURI, state: attempt.state)
        pendingLogin = nil
        webSession = nil
        presentationWindow = nil
        let expectedGeneration = generation
        let response: SpotifyTokenResponse = try await decoded(tokenRequest([
            "client_id": attempt.clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": attempt.redirectURI, "code_verifier": attempt.verifier,
        ]))
        guard generation == expectedGeneration else { throw CancellationError() }
        guard let refresh = response.refreshToken, !refresh.isEmpty else { throw SpotifyError.invalidResponse }
        try save(response, refreshToken: refresh, clientID: attempt.clientID, redirectURI: attempt.redirectURI)
        return true
    }

    static func authorizationCode(from url: URL, redirectURI: String, state: String) throws -> String {
        guard var actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(string: redirectURI), actual.fragment == nil else {
            throw SpotifyError.invalidCallback
        }
        let items = actual.queryItems ?? []
        actual.query = nil
        guard actual == expected,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else {
            throw SpotifyError.invalidCallback
        }
        if items.contains(where: { $0.name == "error" }) { throw SpotifyError.authorizationDenied }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty else {
            throw SpotifyError.missingAuthorizationCode
        }
        return code
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
        var request = URLRequest(url: apiURL(path: "/me/player/play"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["uris": [trackURI]])
        _ = try await authorizedData(request)
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
        var components = URLComponents(url: apiURL(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return try JSONDecoder().decode(T.self, from: await authorizedData(URLRequest(url: components.url!)))
    }

    private func authorizedData(_ request: URLRequest) async throws -> Data {
        let expectedGeneration = generation
        var request = request
        var token = try await validToken()
        guard generation == expectedGeneration else { throw CancellationError() }
        for attempt in 0...1 {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let data = try await data(for: request)
                guard generation == expectedGeneration else { throw CancellationError() }
                return data
            } catch let error as SpotifyHTTPError where error.status == 401 {
                guard generation == expectedGeneration else { throw CancellationError() }
                if attempt == 1 {
                    try disconnect()
                    throw SpotifyError.notAuthenticated
                }
                // A concurrent request may already have replaced the rejected access token.
                token = try await validToken(rejectedToken: token)
            }
        }
        throw SpotifyError.notAuthenticated
    }

    private func validToken(rejectedToken: String? = nil) async throws -> String {
        guard let saved = credentials else { throw SpotifyError.notAuthenticated }
        if saved.expiresAt.timeIntervalSinceNow > 60, saved.accessToken != rejectedToken {
            return saved.accessToken
        }
        if let refreshTask { return try await refreshTask.value }
        let expectedGeneration = generation
        let task = Task<String, Error> { @MainActor in
            do {
                let response: SpotifyTokenResponse = try await self.decoded(self.tokenRequest([
                    "grant_type": "refresh_token", "refresh_token": saved.refreshToken,
                    "client_id": saved.clientID,
                ]))
                guard self.generation == expectedGeneration else { throw CancellationError() }
                let refresh = response.refreshToken ?? saved.refreshToken
                try self.save(response, refreshToken: refresh, clientID: saved.clientID, redirectURI: saved.redirectURI)
                return response.accessToken
            } catch let error as SpotifyHTTPError {
                guard self.generation == expectedGeneration else { throw CancellationError() }
                if error.oauthCode == "invalid_grant" || error.status == 401 {
                    try self.disconnect()
                    throw SpotifyError.notAuthenticated
                }
                throw error
            }
        }
        refreshTask = task
        defer { if generation == expectedGeneration { refreshTask = nil } }
        return try await task.value
    }

    private func save(_ token: SpotifyTokenResponse, refreshToken: String, clientID: String, redirectURI: String) throws {
        guard !token.accessToken.isEmpty, !refreshToken.isEmpty, token.expiresIn > 0 else {
            throw SpotifyError.invalidResponse
        }
        let saved = SpotifyCredentials(accessToken: token.accessToken, refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)), clientID: clientID, redirectURI: redirectURI)
        try tokenStore.save(saved)
        credentials = saved
        onConnectionChanged?(true)
    }

    private func apiURL(path: String) -> URL {
        path.split(separator: "/").reduce(apiBaseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private func data(for request: URLRequest) async throws -> Data {
        let expectedGeneration = generation
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            guard generation == expectedGeneration else { throw CancellationError() }
            throw error
        }
        guard generation == expectedGeneration else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyHTTPError(response: http, data: data)
        }
        return data
    }

    private func decoded<T: Decodable>(_ request: URLRequest) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(for: request))
    }

    private func tokenRequest(_ values: [String: String]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(values.sorted(by: { $0.key < $1.key }).map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        return request
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
        // Retained before start(), and released only after the browser has finished.
        guard let presentationWindow else {
            preconditionFailure("Spotify authentication started without an active window")
        }
        return presentationWindow
    }
}

private struct LoginAttempt: Sendable {
    let clientID: String
    let redirectURI: String
    let verifier: String
    let state: String
}

struct SpotifyCredentials: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let clientID: String
    let redirectURI: String
}

protocol SpotifyTokenStore {
    func load() throws -> SpotifyCredentials?
    func save(_ credentials: SpotifyCredentials) throws
    func delete() throws
}

struct KeychainSpotifyTokenStore: SpotifyTokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Health2BPM.Spotify", kSecAttrAccount as String: "session"]
    }

    func load() throws -> SpotifyCredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SpotifyError.keychain(status) }
        return try JSONDecoder().decode(SpotifyCredentials.self, from: data)
    }

    func save(_ credentials: SpotifyCredentials) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw SpotifyError.keychain(result) }
        } else if status != errSecSuccess { throw SpotifyError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SpotifyError.keychain(status) }
    }
}

struct SpotifyHTTPError: LocalizedError, Sendable {
    let status: Int
    let oauthCode: String?
    let retryAfter: String?
    let endpoint: String

    init(response: HTTPURLResponse, data: Data) {
        status = response.statusCode
        endpoint = response.url?.path ?? ""
        retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        oauthCode = body?["error"] as? String
    }

    var errorDescription: String? {
        let detail: String
        switch status {
        case 401: detail = "認証の有効期限が切れました。再ログインしてください"
        case 403: detail = "アクセスが拒否されました。利用者登録・権限・APIの利用条件を確認してください"
        case 404 where endpoint.hasSuffix("/player/play"):
            detail = "再生先が見つかりません。Spotifyで曲を一度再生してください"
        case 429: detail = "リクエスト上限に達しました。時間をおいて再試行してください" + (retryAfter.map { "（Retry-After: \($0)）" } ?? "")
        default:
            switch oauthCode {
            case "invalid_grant": detail = "認証が無効になりました。再ログインしてください"
            case "invalid_client": detail = "Client IDを確認してください"
            default: detail = "Spotifyとの通信に失敗しました"
            }
        }
        // Do not display raw token responses or arbitrary server error bodies.
        return "HTTP \(status): \(detail)"
    }
}

enum SpotifyError: LocalizedError, Sendable {
    case missingAuthorizationCode, notAuthenticated, seedTrackNotFound, invalidCallback
    case loginUnavailable, loginCancelled, authorizationDenied, invalidResponse
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAuthorizationCode: "認証コードが見つかりません"
        case .notAuthenticated: "Spotifyに再ログインしてください"
        case .seedTrackNotFound: "ムードに合う曲が見つかりません"
        case .invalidCallback: "認証の戻り先またはstateが一致しません。再ログインしてください"
        case .loginUnavailable: "認証画面を開けませんでした。アプリを開いて再試行してください"
        case .loginCancelled: "Spotify認証をキャンセルしました"
        case .authorizationDenied: "Spotifyへのアクセスが許可されませんでした"
        case .invalidResponse: "Spotifyからの応答を読み取れませんでした"
        case .keychain(let status): "認証情報の保存・読み込みに失敗しました（\(status)）"
        }
    }
}
