import SwiftUI

struct WelcomeRootView: View {
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some View {
        if hasCompletedWelcome {
            ContentView()
        } else {
            WelcomeView { hasCompletedWelcome = true }
        }
    }
}

/// A self-contained introduction. It never starts measurement or Spotify authentication.
struct WelcomeView: View {
    var onComplete: () -> Void
    @State private var selection = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34

    private let titles = ["心拍に合う\n音楽を。", "いまの気分に\nフィットする。", "どんなシーンでも\nもっと心地よく。"]
    private let descriptions = [
        "あなたの心拍から、\nぴったりのBPMの楽曲を提案します。",
        "Apple Watchで測った心拍から、\nあなたに合うテンポの楽曲をセレクト。",
        "ランニング、リラックス、集中…\nシーンに合わせた音楽を見つけよう。"
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(0..<titles.count, id: \.self) { index in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                WelcomeHero(page: index)
                                    .frame(height: max(240, min(520, geometry.size.height * 0.60)))
                                VStack(alignment: .leading, spacing: 18) {
                                    Text(titles[index])
                                        .font(.system(size: titleSize, weight: .bold))
                                        .tracking(-0.8)
                                        .accessibilityAddTraits(.isHeader)
                                    Text(descriptions[index])
                                        .font(.body)
                                        .foregroundStyle(Color(white: 0.38))
                                        .lineSpacing(4)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 20)
                            }
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    HStack(spacing: 0) {
                        ForEach(0..<titles.count, id: \.self) { index in
                            Button { move(to: index) } label: {
                                Circle()
                                    .fill(selection == index ? Color(white: 0.1) : Color(white: 0.82))
                                    .frame(width: 10, height: 10)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(index + 1)ページ目")
                            .accessibilityValue(selection == index ? "選択中" : "")
                        }
                    }
                    Button {
                        if selection == titles.count - 1 {
                            onComplete()
                        } else {
                            move(to: selection + 1)
                        }
                    } label: {
                        Text(selection == 1 ? "つづける" : "はじめる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 20)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.right")
                                    .font(.body.weight(.semibold))
                                    .padding(.trailing, 24)
                            }
                            .foregroundStyle(.white)
                            .background(Color(white: 0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(selection == 2 ? "音楽を選ぶ画面を開きます" : "次の説明へ進みます")
                }
                .frame(maxWidth: 556)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .foregroundStyle(Color(white: 0.08))
        }
        // The reference uses a light canvas; keep status-bar contrast consistent.
        .preferredColorScheme(.light)
    }

    private func move(to page: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            selection = page
        }
    }
}

private struct WelcomeHero: View {
    let page: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if page < 2 {
                    Image(page == 0 ? "WelcomeHeart" : "WelcomeRunner")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0.89, green: 0.94, blue: 1), .white,
                                            Color(red: 0.78, green: 0.85, blue: 0.93)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    WelcomeCards()
                }

                if page == 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Health2BPM").font(.title2.weight(.regular))
                        Text("Music for a healthier you")
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.35))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(32)
                } else if page == 1 {
                    VStack(spacing: 0) {
                        Text("142").font(.system(size: 72, weight: .light))
                        Text("BPM").font(.title3)
                        Text("測定イメージ").font(.caption2).padding(.top, 8)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6)
                    .position(x: geometry.size.width * 0.78, y: geometry.size.height * 0.40)
                }
            }
        }
        .clipShape(WelcomeWave())
        .accessibilityHidden(true)
    }
}

private struct WelcomeWave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addCurve(to: CGPoint(x: 0, y: rect.height * 0.86),
                          control1: CGPoint(x: rect.width * 0.62, y: rect.height * 0.78),
                          control2: CGPoint(x: rect.width * 0.16, y: rect.height * 1.04))
            path.closeSubpath()
        }
    }
}

private struct WelcomeCards: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                moodCard("Focus", bpm: "96 BPM", symbol: "moon.stars.fill", color: .indigo)
                    .frame(width: width * 0.40, height: geometry.size.height * 0.58)
                    .rotationEffect(.degrees(10))
                    .position(x: width * 0.04, y: geometry.size.height * 0.48)
                moodCard("Chill", bpm: "72 BPM", symbol: "leaf.fill", color: .teal)
                    .frame(width: width * 0.40, height: geometry.size.height * 0.58)
                    .rotationEffect(.degrees(8))
                    .position(x: width * 0.96, y: geometry.size.height * 0.55)
                ZStack(alignment: .bottom) {
                    GeometryReader { card in
                        Image("WelcomeSea")
                            .resizable().scaledToFill()
                            .frame(width: card.size.width, height: card.size.height)
                            .clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                   startPoint: .center, endPoint: .bottom)
                    VStack(spacing: 6) {
                        Text("Morning Boost").font(.system(size: 21, weight: .medium))
                        Text("128 BPM").font(.system(size: 13))
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40)).padding(.top, 8)
                        Text("楽曲提案のイメージ").font(.system(size: 10))
                    }
                    .foregroundStyle(.white)
                    .padding(.bottom, 22)
                }
                .frame(width: width * 0.58, height: geometry.size.height * 0.75)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .blue.opacity(0.14), radius: 24, y: 18)
                .rotationEffect(.degrees(8))
                .position(x: width * 0.52, y: geometry.size.height * 0.46)
            }
        }
        .clipped()
    }

    private func moodCard(_ title: String, bpm: String, symbol: String, color: Color) -> some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.65), Color(white: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 38)).padding(.top, 25)
                Spacer()
                Text(title).font(.system(size: 18, weight: .medium))
                Text(bpm).font(.system(size: 12))
            }
            .padding(24)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

#Preview("Welcome") {
    WelcomeView(onComplete: {})
}
