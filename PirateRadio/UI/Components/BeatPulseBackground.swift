import SwiftUI

/// Slow, organic pulsing background that fills the entire screen.
/// Large warped blobs breathe and drift behind all UI, with
/// subtle ring expansions and a CRT scan line.
struct BeatPulseBackground: View {
    var isPlaying: Bool

    @State private var bpm: Double = 128
    @State private var breathePhase: Bool = false
    @State private var ringTrigger: Int = 0
    @State private var ringOriginX: CGFloat = -0.05

    private var beatInterval: Double { 60.0 / bpm }

    private var zoneColor: Color {
        if bpm < 100 { return PirateTheme.signal }
        if bpm < 140 { return PirateTheme.flare }
        return PirateTheme.broadcast
    }

    private var secondaryColor: Color {
        if bpm < 100 { return PirateTheme.broadcast }
        if bpm < 140 { return PirateTheme.signal }
        return PirateTheme.flare
    }

    var body: some View {
        GeometryReader { geo in
            // Ring origin tracks the pirate ship's position
            let ringCenter = CGPoint(x: ringOriginX * geo.size.width, y: geo.size.height * 0.65)

            ZStack {
                // Layer 1: Large warped blobs that fill the screen
                WarpBlob(
                    color: zoneColor,
                    baseSize: max(geo.size.width, geo.size.height) * 1.2,
                    anchor: UnitPoint(x: 0.3, y: 0.25),
                    breathePhase: breathePhase,
                    driftSpeed: 20,
                    rotationRange: 30,
                    index: 0
                )

                WarpBlob(
                    color: secondaryColor,
                    baseSize: max(geo.size.width, geo.size.height) * 1.0,
                    anchor: UnitPoint(x: 0.7, y: 0.6),
                    breathePhase: breathePhase,
                    driftSpeed: 25,
                    rotationRange: -45,
                    index: 1
                )

                WarpBlob(
                    color: zoneColor.opacity(0.5),
                    baseSize: max(geo.size.width, geo.size.height) * 0.8,
                    anchor: UnitPoint(x: 0.5, y: 0.85),
                    breathePhase: breathePhase,
                    driftSpeed: 18,
                    rotationRange: 60,
                    index: 2
                )

                // Layer 2: Slow expanding rings from ship position
                ForEach(0..<3, id: \.self) { i in
                    SlowPulseRing(
                        center: ringCenter,
                        color: i.isMultiple(of: 2) ? zoneColor : secondaryColor,
                        delay: Double(i) * 2.0,
                        isPlaying: isPlaying,
                        trigger: ringTrigger
                    )
                }

                // Layer 3: Scan line
                scanLine(size: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            // Slow BPM drift
            while !Task.isCancelled {
                if isPlaying {
                    let newBPM = Double.random(in: 85...160)
                    withAnimation(.easeInOut(duration: Double.random(in: 6...14))) {
                        bpm = newBPM
                    }
                }
                try? await Task.sleep(for: .seconds(Double.random(in: 6...14)))
            }
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            // Slow breathe cycle: 6-10 seconds per phase
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: Double.random(in: 6...10))) {
                    breathePhase.toggle()
                }
                // Trigger ring every few breaths
                ringTrigger += 1
                try? await Task.sleep(for: .seconds(Double.random(in: 6...10)))
            }
        }
        .task {
            // Mirror the pirate ship's 18-second sail across
            while !Task.isCancelled {
                ringOriginX = -0.05
                withAnimation(.linear(duration: 18)) {
                    ringOriginX = 1.05
                }
                try? await Task.sleep(for: .seconds(18))
            }
        }
    }

    // MARK: - Scan Line

    @State private var scanOffset: CGFloat = -1

    private func scanLine(size: CGSize) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, zoneColor.opacity(0.02), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: size.height * 0.4)
            .offset(y: scanOffset * size.height)
            .task {
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 6)) {
                        scanOffset = 1
                    }
                    try? await Task.sleep(for: .seconds(6))
                    scanOffset = -1
                    try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
                }
            }
    }
}

// MARK: - Warp Blob

/// A large, blurred ellipse that slowly warps its shape by animating
/// scaleX/scaleY independently, rotating, and drifting position.
private struct WarpBlob: View {
    let color: Color
    let baseSize: CGFloat
    let anchor: UnitPoint
    let breathePhase: Bool
    let driftSpeed: Double
    let rotationRange: Double
    let index: Int

    @State private var scaleX: CGFloat = 1.0
    @State private var scaleY: CGFloat = 1.0
    @State private var rotation: Double = 0
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(breathePhase ? 0.09 : 0.04),
                        color.opacity(breathePhase ? 0.04 : 0.015),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: baseSize * 0.05,
                    endRadius: baseSize * 0.5
                )
            )
            .frame(width: baseSize, height: baseSize * 0.7)
            .scaleEffect(x: scaleX, y: scaleY)
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
            .opacity(opacity)
            .blur(radius: baseSize * 0.08)
            .position(x: anchor.x * UIScreen.main.bounds.width,
                      y: anchor.y * UIScreen.main.bounds.height)
            .onAppear {
                opacity = 1
                startWarpCycle()
            }
            .onChange(of: breathePhase) { _, _ in
                startWarpCycle()
            }
    }

    private func startWarpCycle() {
        let duration = Double.random(in: 8...15)
        withAnimation(.easeInOut(duration: duration)) {
            // Asymmetric scale creates organic warping
            scaleX = CGFloat.random(in: 0.7...1.4)
            scaleY = CGFloat.random(in: 0.6...1.3)
            rotation = Double.random(in: -abs(rotationRange)...abs(rotationRange))
            offsetX = CGFloat.random(in: -40...40)
            offsetY = CGFloat.random(in: -30...30)
        }
    }
}

// MARK: - Slow Pulse Ring

/// Rings that expand very slowly across the full screen and fade.
private struct SlowPulseRing: View {
    let center: CGPoint
    let color: Color
    let delay: Double
    let isPlaying: Bool
    let trigger: Int

    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0

    var body: some View {
        Ellipse()
            .strokeBorder(color, lineWidth: 1)
            // Slight warp — not a perfect circle
            .frame(width: 250, height: 220)
            .scaleEffect(scale)
            .rotationEffect(.degrees(Double(trigger) * 15))
            .opacity(opacity)
            .position(center)
            .onChange(of: trigger) { _, _ in
                guard isPlaying else { return }
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    scale = 0.2
                    opacity = 0.3
                    // Very slow expansion across full screen
                    withAnimation(.easeOut(duration: 8)) {
                        scale = 6.0
                        opacity = 0
                    }
                }
            }
    }
}
