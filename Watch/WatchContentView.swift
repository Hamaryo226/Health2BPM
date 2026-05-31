import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var heartRateManager: HeartRateManager

    private var bpmText: String {
        heartRateManager.currentBPM.map(String.init) ?? "--"
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 190
            let bpmSize = min(proxy.size.width * 0.38, isCompact ? 46 : 56)

            VStack(spacing: isCompact ? 7 : 9) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Text("Health2BPM")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(heartRateManager.isRunning ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                }

                VStack(spacing: 0) {
                    Text(bpmText)
                        .font(.system(size: bpmSize, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: isCompact ? 58 : 72)
                .padding(.vertical, isCompact ? 4 : 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    heartRateManager.isRunning ? heartRateManager.stop() : heartRateManager.start()
                } label: {
                    Label(
                        heartRateManager.isRunning ? "停止" : "測定開始",
                        systemImage: heartRateManager.isRunning ? "stop.fill" : "heart.fill"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(WatchPrimaryButtonStyle(isDestructive: heartRateManager.isRunning, isCompact: isCompact))

                Text(heartRateManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 14)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct WatchPrimaryButtonStyle: ButtonStyle {
    let isDestructive: Bool
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 38 : 42)
            .background(buttonColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }

    private func buttonColor(isPressed: Bool) -> Color {
        let color = isDestructive ? Color.red : Color.green
        return isPressed ? color.opacity(0.72) : color
    }
}
