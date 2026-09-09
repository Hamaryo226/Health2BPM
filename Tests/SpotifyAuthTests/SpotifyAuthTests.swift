import Foundation
import XCTest
@testable import Health2BPMAuth

@MainActor
final class SpotifyAuthTests: XCTestCase {
    func testCallbackRejectsWrongStateHostAndDuplicateCode() throws {
        let redirect = "health2bpm://spotify-callback"
        XCTAssertEqual(try SpotifyService.authorizationCode(
            from: URL(string: redirect + "?code=abc&state=expected")!,
            redirectURI: redirect, state: "expected"), "abc")
        for callback in [
            redirect + "?code=abc&state=wrong",
            "health2bpm://other?code=abc&state=expected",
            redirect + "?code=a&code=b&state=expected",
            redirect + "?code=abc&state=expected&state=expected",
            redirect + "?code=abc&state=expected#fragment",
        ] {
            XCTAssertThrowsError(try SpotifyService.authorizationCode(
                from: URL(string: callback)!, redirectURI: redirect, state: "expected"))
        }
    }

    func testRestoreAndDisconnect() throws {
        let store = MemoryTokenStore()
        store.value = credentials()
        let service = SpotifyService(tokenStore: store)
        try service.restore(clientID: "client", redirectURI: "health2bpm://spotify-callback")
        XCTAssertTrue(service.isConnected)
        try service.disconnect()
        XCTAssertFalse(service.isConnected)
        XCTAssertNil(store.value)
    }

    func testChangedClientDoesNotRestoreAnotherClientsTokens() throws {
        let store = MemoryTokenStore()
        store.value = credentials()
        let service = SpotifyService(tokenStore: store)
        try service.restore(clientID: "different", redirectURI: "health2bpm://spotify-callback")
        XCTAssertFalse(service.isConnected)
        XCTAssertNil(store.value)
    }

    func testExpiredTokenRefreshRetainsRefreshTokenWhenOmitted() async throws {
        let store = MemoryTokenStore()
        store.value = credentials()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyStubProtocol.self]
        let service = SpotifyService(session: URLSession(configuration: config), tokenStore: store)
        try service.restore(clientID: "client", redirectURI: "health2bpm://spotify-callback")
        try await service.play(trackURI: "spotify:track:test")
        XCTAssertEqual(store.value?.accessToken, "new-access")
        XCTAssertEqual(store.value?.refreshToken, "original-refresh")
        XCTAssertGreaterThan(store.value!.expiresAt, Date())
    }

    func testUnauthorizedTokenIsRefreshedAndPlaybackRetried() async throws {
        let store = MemoryTokenStore()
        store.value = SpotifyCredentials(accessToken: "rejected", refreshToken: "original-refresh",
            expiresAt: Date().addingTimeInterval(3600), clientID: "client",
            redirectURI: "health2bpm://spotify-callback")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyStubProtocol.self]
        let service = SpotifyService(session: URLSession(configuration: config), tokenStore: store)
        try service.restore(clientID: "client", redirectURI: "health2bpm://spotify-callback")
        try await service.play(trackURI: "spotify:track:test")
        XCTAssertEqual(store.value?.accessToken, "new-access")
    }

    func testHTTPErrorDoesNotExposeArbitraryResponseBody() {
        let response = HTTPURLResponse(url: URL(string: "https://api.spotify.com/v1/recommendations")!,
                                       statusCode: 403, httpVersion: nil, headerFields: nil)!
        let error = SpotifyHTTPError(response: response, data: Data("{\"error\":{\"message\":\"secret-token\"}}".utf8))
        XCTAssertTrue(error.localizedDescription.contains("403"))
        XCTAssertFalse(error.localizedDescription.contains("secret-token"))
    }

    func testLibraryAndPlaylistRequestsRefreshExpiredCredentials() async throws {
        let store = MemoryTokenStore()
        store.value = credentials()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyStubProtocol.self]
        let service = SpotifyService(session: URLSession(configuration: config), tokenStore: store)
        try service.restore(clientID: "client", redirectURI: "health2bpm://spotify-callback")
        try await service.saveFavorite(trackURI: "spotify:track:test")
        let playlist = try await service.createPlaylist(name: "  Test  ")
        XCTAssertEqual(playlist.id, "created")
        try await service.savePlaylistTracks(playlistID: playlist.id, uris: ["spotify:track:test"])
        // Retrying a replacement must target the same playlist.
        try await service.savePlaylistTracks(playlistID: playlist.id, uris: ["spotify:track:test"])
        XCTAssertEqual(store.value?.accessToken, "new-access")
    }

    func testEmptyPlaylistInputIsRejectedBeforeAuthentication() async {
        let service = SpotifyService(tokenStore: MemoryTokenStore())
        do {
            _ = try await service.createPlaylist(name: " \n ")
            XCTFail("Expected validation failure")
        } catch {
            guard case SpotifyError.invalidPlaylist = error else { return XCTFail("\(error)") }
        }
        do {
            try await service.savePlaylistTracks(playlistID: "created", uris: [])
            XCTFail("Expected validation failure")
        } catch {
            guard case SpotifyError.invalidPlaylist = error else { return XCTFail("\(error)") }
        }
    }

    private func credentials() -> SpotifyCredentials {
        SpotifyCredentials(accessToken: "expired", refreshToken: "original-refresh", expiresAt: .distantPast,
                           clientID: "client", redirectURI: "health2bpm://spotify-callback")
    }
}

private final class MemoryTokenStore: SpotifyTokenStore {
    var value: SpotifyCredentials?
    func load() throws -> SpotifyCredentials? { value }
    func save(_ credentials: SpotifyCredentials) throws { value = credentials }
    func delete() throws { value = nil }
}

private final class SpotifyStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isToken = request.url?.path == "/api/token"
        let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access"
        let status = isToken ? 200 : (authorized ? 204 : 401)
        var body = isToken ? "{\"access_token\":\"new-access\",\"expires_in\":3600}" : ""
        if authorized {
            switch request.url?.path {
            case "/v1/me/library":
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "uris" })?.value, "spotify:track:test")
            case "/v1/me/playlists":
                XCTAssertEqual(request.httpMethod, "POST")
                let json = requestJSON()
                XCTAssertEqual(json?["name"] as? String, "Test")
                XCTAssertEqual(json?["public"] as? Bool, false)
                body = "{\"id\":\"created\",\"external_urls\":{\"spotify\":\"https://open.spotify.com/playlist/created\"}}"
            case "/v1/playlists/created/items":
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(requestJSON()?["uris"] as? [String], ["spotify:track:test"])
            default: break
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private func requestJSON() -> [String: Any]? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
