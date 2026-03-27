import SwiftUI

/// Mini speedometer-style BPM gauge with colored zones.
struct BPMGauge: View {
    var isPlaying: Bool
    var size: CGFloat = 80

    @State private var currentBPM: Double = 128
    @State private var targetBPM: Double = 128

    private var zoneColor: Color {
        if currentBPM < 100 { return PirateTheme.signal }      // Chill
        if currentBPM < 140 { return PirateTheme.flare }       // Cruise
        return PirateTheme.broadcast                             // Sprint
    }

    private var normalizedBPM: Double {
        // Map 60-180 BPM to 0-1
        max(0, min(1, (currentBPM - 60) / 120))
    }

    var body: some View {
        ZStack {
            // Background arc
            arcPath
                .stroke(.white.opacity(0.1), lineWidth: 4)

            // Zone arcs
            zoneArcs

            // Active fill arc
            arcPath
                .trim(from: 0, to: normalizedBPM)
                .stroke(zoneColor, lineWidth: 4)

            // Needle
            needle

            // BPM label
            VStack(spacing: 0) {
                Spacer()
                Text("\(Int(currentBPM))")
                    .font(PirateTheme.display(size * 0.17))
                    .foregroundStyle(zoneColor)
                Text("BPM")
                    .font(PirateTheme.body(size * 0.09))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(height: size * 0.75)
        }
        .frame(width: size, height: size * 0.6)
        .neonGlow(zoneColor, intensity: 0.2)
        .task {
            while !Task.isCancelled {
                if isPlaying {
                    // Oscillate between zones for demo
                    targetBPM = Double.random(in: 80...165)
                    withAnimation(.easeInOut(duration: Double.random(in: 3...8))) {
                        currentBPM = targetBPM
                    }
                }
                try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
            }
        }
    }

    private var arcPath: Path {
        Path { path in
            path.addArc(
                center: CGPoint(x: size / 2, y: size * 0.55),
                radius: size * 0.4,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
    }

    private var zoneArcs: some View {
        ZStack {
            // Chill zone (0-33%)
            arcPath
                .trim(from: 0, to: 0.33)
                .stroke(PirateTheme.signal.opacity(0.15), lineWidth: 4)

            // Cruise zone (33-66%)
            arcPath
                .trim(from: 0.33, to: 0.66)
                .stroke(PirateTheme.flare.opacity(0.15), lineWidth: 4)

            // Sprint zone (66-100%)
            arcPath
                .trim(from: 0.66, to: 1.0)
                .stroke(PirateTheme.broadcast.opacity(0.15), lineWidth: 4)
        }
    }

    private var needle: some View {
        let angle = Angle.degrees(180 + normalizedBPM * 180)
        let center = CGPoint(x: size / 2, y: size * 0.55)
        let needleLength = size * 0.3

        return Path { path in
            let endX = center.x + needleLength * cos(angle.radians)
            let endY = center.y + needleLength * sin(angle.radians)
            path.move(to: center)
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(zoneColor, lineWidth: 2)
        .shadow(color: zoneColor.opacity(0.5), radius: 4)
    }
}
