import SwiftUI

/// Animated track progress bar with elapsed/remaining time labels.
struct TrackProgressBar: View {
    let durationMs: Int
    let initialPositionMs: Double
    let isPlaying: Bool

    @State private var elapsedMs: Double = 0

    private var progress: Double {
        guard durationMs > 0 else { return 0 }
        return min(elapsedMs / Double(durationMs), 1.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Bar
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PirateTheme.signal.opacity(0.15))
                        .frame(height: 4)

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PirateTheme.signal)
                        .frame(width: max(0, width * progress), height: 4)
                        .neonGlow(PirateTheme.signal, intensity: isPlaying ? 0.4 : 0.1)
                }
                .frame(height: 20)
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(formatTime(Int(elapsedMs)))
                    .font(PirateTheme.body(11))
                    .foregroundStyle(PirateTheme.signal.opacity(0.7))
                    .monospacedDigit()

                Spacer()

                Text(formatTime(durationMs))
                    .font(PirateTheme.body(11))
                    .foregroundStyle(.white.opacity(0.3))
                    .monospacedDigit()
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if !playing { /* pause: freeze current time */ }
        }
        .onAppear {
            elapsedMs = initialPositionMs
        }
        .task {
            // Animate progress using a timer
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                if isPlaying {
                    withAnimation(.linear(duration: 0.5)) {
                        elapsedMs = min(elapsedMs + 500, Double(durationMs))
                    }
                }
            }
        }
    }

    private func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
