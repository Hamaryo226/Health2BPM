import Foundation

enum Mood: String, CaseIterable, Identifiable, Codable {
    case focus
    case run
    case calm
    case boost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "集中"
        case .run: "走る"
        case .calm: "落ち着く"
        case .boost: "気分を上げる"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: "作業に入りやすい、粒立ちのよいテンポ"
        case .run: "前に進む感じを強める高揚感"
        case .calm: "呼吸を整える柔らかい曲調"
        case .boost: "少し明るく、体が動き出すムード"
        }
    }

    var seedQuery: String {
        switch self {
        case .focus: "focus electronic japanese"
        case .run: "running workout pop"
        case .calm: "calm chill ambient"
        case .boost: "happy dance pop"
        }
    }

    var spotifyTuning: [String: String] {
        switch self {
        case .focus:
            ["target_energy": "0.55", "target_danceability": "0.58", "target_valence": "0.46"]
        case .run:
            ["target_energy": "0.86", "target_danceability": "0.76", "target_valence": "0.68"]
        case .calm:
            ["target_energy": "0.32", "target_danceability": "0.38", "target_valence": "0.42"]
        case .boost:
            ["target_energy": "0.74", "target_danceability": "0.82", "target_valence": "0.82"]
        }
    }
}

struct RecommendedTrack: Identifiable, Hashable {
    let id: String
    let name: String
    let artists: String
    let albumName: String
    let artworkURL: URL?
    let spotifyURL: URL
    let uri: String
    let durationSeconds: Int
}

struct WatchHeartRateMessage {
    static let bpm = "bpm"
    static let timestamp = "timestamp"
}
