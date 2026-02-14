import SwiftUI

/// Animated track progress bar with elapsed/remaining time labels and DJ scrubbing.
struct TrackProgressBar: View {
    let durationMs: Int
    let isPlaying: Bool
    let isDJ: Bool

    @State private var elapsedMs: Double = 0
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var onSeek: ((Int) -> Void)?

    private var progress: Double {
        guard durationMs > 0 else { return 0 }
        return isDragging ? dragProgress : min(elapsedMs / Double(durationMs), 1.0)
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

                    // DJ scrubbing thumb
                    if isDJ {
                        Circle()
                            .fill(PirateTheme.signal)
                            .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                            .neonGlow(PirateTheme.signal, intensity: 0.6)
                            .offset(x: max(0, width * progress - 5))
                            .animation(.easeOut(duration: 0.15), value: isDragging)
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(isDJ ? scrubGesture(width: width) : nil)
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(formatTime(Int(isDragging ? dragProgress * Double(durationMs) : elapsedMs)))
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
            // Start with a random position for demo effect
            elapsedMs = Double.random(in: 30_000...90_000)
        }
        .task {
            // Animate progress using a timer
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                if isPlaying && !isDragging {
                    withAnimation(.linear(duration: 0.5)) {
                        elapsedMs = min(elapsedMs + 500, Double(durationMs))
                    }
                    // Loop for demo
                    if elapsedMs >= Double(durationMs) {
                        elapsedMs = 0
                    }
                }
            }
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                dragProgress = max(0, min(1, value.location.x / width))
            }
            .onEnded { _ in
                let seekPosition = Int(dragProgress * Double(durationMs))
                elapsedMs = Double(seekPosition)
                isDragging = false
                onSeek?(seekPosition)
            }
    }

    private func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
