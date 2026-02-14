import SwiftUI

/// Animated CRT static noise overlay.
/// Uses a `TimelineView` with a `Canvas` to render random grayscale dots
/// that simulate analog television static.
///
/// - Parameter intensity: 0.0 = fully clear, 1.0 = full static.
struct CRTStaticOverlay: View {
    let intensity: Double

    /// How many horizontal / vertical cells to divide the canvas into.
    private let columns = 64
    private let rows = 96

    var body: some View {
        if intensity > 0.001 {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                Canvas { context, size in
                    let cellW = size.width / CGFloat(columns)
                    let cellH = size.height / CGFloat(rows)

                    // Seed changes each frame so the noise animates.
                    // We don't need true randomness — visual jitter is enough.
                    let seed = timeline.date.timeIntervalSinceReferenceDate

                    for row in 0..<rows {
                        for col in 0..<columns {
                            let hash = pseudoRandom(x: col, y: row, seed: seed)
                            let brightness = hash * intensity
                            let rect = CGRect(
                                x: CGFloat(col) * cellW,
                                y: CGFloat(row) * cellH,
                                width: cellW + 0.5,  // slight overlap to avoid gaps
                                height: cellH + 0.5
                            )
                            context.fill(
                                Path(rect),
                                with: .color(Color.white.opacity(brightness * 0.7))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .opacity(intensity)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    /// Fast pseudo-random value in 0...1 based on cell position and a time seed.
    private func pseudoRandom(x: Int, y: Int, seed: Double) -> Double {
        // Simple hash combining position + time
        let n = sin(Double(x * 127 + y * 311) + seed * 43758.5453123)
        return abs(n.truncatingRemainder(dividingBy: 1.0))
    }
}

#Preview {
    ZStack {
        PirateTheme.void.ignoresSafeArea()
        Text("SIGNAL LOST")
            .font(PirateTheme.display(28))
            .foregroundStyle(PirateTheme.signal)
        CRTStaticOverlay(intensity: 0.6)
            .ignoresSafeArea()
    }
}
