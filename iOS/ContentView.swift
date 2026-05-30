import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            TabView(selection: $appState.step) {
                MoodSelectionView()
                    .tabItem {
                        Label("ムード", systemImage: "sparkles")
                    }
                    .tag(AppState.Step.mood)

                HeartRateView()
                    .tabItem {
                        Label("心拍", systemImage: "heart.fill")
                    }
                    .tag(AppState.Step.heartRate)

                SpotifyConnectView()
                    .tabItem {
                        Label("Spotify", systemImage: "music.note")
                    }
                    .tag(AppState.Step.spotify)

                SuggestionsView()
                    .tabItem {
                        Label("提案", systemImage: "rectangle.stack.fill")
                    }
                    .tag(AppState.Step.suggestions)
            }
            .tint(.green)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(appState.step.navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                NavigationLink {
                    SpotifySettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .accessibilityLabel("Spotify API設定")
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct MoodSelectionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScreenScroll {
            StatusPill(message: appState.statusMessage)

            HeaderBlock(
                title: "いま欲しいムード",
                subtitle: "気分とApple Watchの心拍数に近いBPMで、Spotifyから10曲を提案します。"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                ForEach(Mood.allCases) { mood in
                    Button {
                        appState.selectMood(mood)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: mood.symbolName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.green)
                            Spacer(minLength: 4)
                            Text(mood.title)
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                            Text(mood.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                        }
                        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                        .padding(18)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }
}

private struct HeartRateView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScreenScroll {
            StatusPill(message: appState.statusMessage)

            HeaderBlock(
                title: "心拍数を測定",
                subtitle: "Apple Watchアプリで測定開始を押すと、iPhoneへBPMが送信されます。"
            )

            VStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.green)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(appState.latestBPM.map(String.init) ?? "--")
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button("このBPMでSpotifyへ進む") {
                appState.continueToSpotify()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(appState.latestBPM == nil)
        }
    }
}

private struct SpotifyConnectView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScreenScroll {
            StatusPill(message: appState.statusMessage)

            HeaderBlock(
                title: "Spotifyへ接続",
                subtitle: "保存したAPI設定を使ってログインし、心拍数に近い曲を提案します。"
            )

            VStack(spacing: 0) {
                SettingRow(title: "Client ID", value: appState.clientID.isEmpty ? "未設定" : "設定済み")
                Divider()
                SettingRow(title: "Market", value: appState.market)
                Divider()
                SettingRow(title: "Redirect URI", value: appState.redirectURI)
            }
            .padding(.horizontal, 16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            NavigationLink {
                SpotifySettingsView()
            } label: {
                Label("Spotify API設定を開く", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Spotifyにログインして10曲提案") {
                appState.loginToSpotify()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(appState.isLoading)
        }
    }
}

private struct SuggestionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScreenScroll {
            StatusPill(message: appState.statusMessage)

            if let track = appState.currentTrack {
                AsyncImage(url: track.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color(.secondarySystemGroupedBackground)
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(track.artists)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("\(track.albumName) · \(track.durationSeconds)秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(min(appState.currentTrackIndex + 1, appState.tracks.count)) / \(appState.tracks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    Button("再生する") {
                        appState.playCurrentTrack()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("次の曲") {
                        appState.skipTrack()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                ContentUnavailableView("候補がありません", systemImage: "music.note", description: Text("Spotifyに接続すると、ここに提案曲が表示されます。"))
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

private struct SpotifySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                TextField("Spotify Client ID", text: $appState.clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Redirect URI", text: $appState.redirectURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Market", text: $appState.market)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Spotify API")
            } footer: {
                Text("Spotify Developer DashboardのRedirect URIに、ここに表示されている値を完全一致で登録してください。通常は health2bpm://spotify-callback です。")
            }

            Section {
                Button {
                    UIPasteboard.general.string = appState.redirectURI
                    appState.statusMessage = "Redirect URIをコピーしました"
                } label: {
                    Label("Redirect URIをコピー", systemImage: "doc.on.doc")
                }

                Button("設定を保存") {
                    appState.saveSpotifySettings()
                }
                .font(.headline)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Spotify API設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ScreenScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct HeaderBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusPill: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "waveform.path.ecg")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 13)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? Color.green.opacity(0.72) : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

private extension AppState.Step {
    var navigationTitle: String {
        switch self {
        case .mood: "Health2BPM"
        case .heartRate: "心拍"
        case .spotify: "Spotify"
        case .suggestions: "提案"
        }
    }
}

private extension Mood {
    var symbolName: String {
        switch self {
        case .focus: "target"
        case .run: "figure.run"
        case .calm: "leaf.fill"
        case .boost: "bolt.heart.fill"
        }
    }
}
