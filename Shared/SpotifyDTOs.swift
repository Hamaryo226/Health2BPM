import Foundation

struct SpotifyCreatedPlaylist: Decodable {
    let id: String
    let externalURLs: [String: URL]

    enum CodingKeys: String, CodingKey {
        case id
        case externalURLs = "external_urls"
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyTrackPage
}

struct SpotifyRecommendationResponse: Decodable {
    let tracks: [SpotifyTrackDTO]
}

struct SpotifyTrackPage: Decodable {
    let items: [SpotifyTrackDTO]
}

struct SpotifyTrackDTO: Decodable {
    let id: String
    let name: String
    let uri: String
    let durationMS: Int
    let artists: [SpotifyArtistDTO]
    let album: SpotifyAlbumDTO
    let externalURLs: [String: URL]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case uri
        case durationMS = "duration_ms"
        case artists
        case album
        case externalURLs = "external_urls"
    }

    var recommendedTrack: RecommendedTrack? {
        guard let spotifyURL = externalURLs["spotify"] else { return nil }
        return RecommendedTrack(
            id: id,
            name: name,
            artists: artists.map(\.name).joined(separator: ", "),
            albumName: album.name,
            artworkURL: album.images.first?.url,
            spotifyURL: spotifyURL,
            uri: uri,
            durationSeconds: durationMS / 1000
        )
    }
}

struct SpotifyArtistDTO: Decodable {
    let name: String
}

struct SpotifyAlbumDTO: Decodable {
    let name: String
    let images: [SpotifyImageDTO]
}

struct SpotifyImageDTO: Decodable {
    let url: URL
}
