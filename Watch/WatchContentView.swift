import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var heartRateManager: HeartRateManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Health2BPM")
                    .font(.headline)

                Text(heartRateManager.currentBPM.map(String.init) ?? "--")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())

                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    heartRateManager.isRunning ? heartRateManager.stop() : heartRateManager.start()
                } label: {
                    Text(heartRateManager.isRunning ? "停止" : "測定開始")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .contentShape(Rectangle())

                Text(heartRateManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
        }
    }
}
