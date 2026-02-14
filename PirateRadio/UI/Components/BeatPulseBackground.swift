import SwiftUI

/// Layered pulsing background that reacts to BPM.
/// Concentric rings expand outward, radial gradients breathe,
/// and floating orbs drift — all synced to the beat.
struct BeatPulseBackground: View {
    var isPlaying: Bool

    @State private var bpm: Double = 128
    @State private var beatPhase: Bool = false
    @State private var ringTrigger: Int = 0

    private var beatInterval: Double { 60.0 / bpm }

    private var zoneColor: Color {
        if bpm < 100 { return PirateTheme.signal }
        if bpm < 140 { return PirateTheme.flare }
        return PirateTheme.broadcast
    }

    private var secondaryColor: Color {
        if bpm < 100 { return PirateTheme.broadcast.opacity(0.3) }
        if bpm < 140 { return PirateTheme.signal.opacity(0.3) }
        return PirateTheme.flare.opacity(0.3)
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.35, y: geo.size.height * 0.28)

            ZStack {
                // Layer 1: Deep radial breathing gradient
                breathingGradient(center: center, size: geo.size)

                // Layer 2: Expanding rings from album art center
                ForEach(0..<4, id: \.self) { i in
                    PulseRing(
                        center: center,
                        color: i.isMultiple(of: 2) ? zoneColor : secondaryColor,
                        delay: Double(i) * beatInterval * 0.25,
                        beatInterval: beatInterval,
                        isPlaying: isPlaying,
                        trigger: ringTrigger
                    )
                }

                // Layer 3: Floating orbs
                ForEach(0..<6, id: \.self) { i in
                    FloatingOrb(
                        index: i,
                        bounds: geo.size,
                        color: i.isMultiple(of: 3) ? zoneColor : secondaryColor,
                        beatInterval: beatInterval,
                        isPlaying: isPlaying
                    )
                }

                // Layer 4: Subtle vertical scan line
                scanLine(size: geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            while !Task.isCancelled {
                if isPlaying {
                    // BPM drift for variety
                    let newBPM = Double.random(in: 85...160)
                    withAnimation(.easeInOut(duration: Double.random(in: 4...10))) {
                        bpm = newBPM
                    }
                }
                try? await Task.sleep(for: .seconds(Double.random(in: 4...10)))
            }
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: beatInterval * 0.3)) {
                    beatPhase.toggle()
                }
                ringTrigger += 1
                try? await Task.sleep(for: .seconds(beatInterval))
            }
        }
    }

    // MARK: - Breathing Gradient

    private func breathingGradient(center: CGPoint, size: CGSize) -> some View {
        let radius = max(size.width, size.height) * (beatPhase ? 0.7 : 0.55)
        return RadialGradient(
            gradient: Gradient(colors: [
                zoneColor.opacity(beatPhase ? 0.08 : 0.03),
                secondaryColor.opacity(0.02),
                Color.clear,
            ]),
            center: UnitPoint(
                x: center.x / size.width,
                y: center.y / size.height
            ),
            startRadius: 20,
            endRadius: radius
        )
        .animation(.easeInOut(duration: beatInterval * 0.5), value: beatPhase)
    }

    // MARK: - Scan Line

    @State private var scanOffset: CGFloat = -1

    private func scanLine(size: CGSize) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, zoneColor.opacity(0.03), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: size.height * 0.3)
            .offset(y: scanOffset * size.height)
            .task {
                while !Task.isCancelled {
                    withAnimation(.linear(duration: 4)) {
                        scanOffset = 1
                    }
                    try? await Task.sleep(for: .seconds(4))
                    scanOffset = -1
                    try? await Task.sleep(for: .seconds(Double.random(in: 1...3)))
                }
            }
    }
}

// MARK: - Pulse Ring

private struct PulseRing: View {
    let center: CGPoint
    let color: Color
    let delay: Double
    let beatInterval: Double
    let isPlaying: Bool
    let trigger: Int

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.5)
            .frame(width: 200, height: 200)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(center)
            .onChange(of: trigger) { _, _ in
                guard isPlaying else { return }
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    // Reset
                    scale = 0.3
                    opacity = 0.6
                    // Expand and fade
                    withAnimation(.easeOut(duration: beatInterval * 2.5)) {
                        scale = 3.5
                        opacity = 0
                    }
                }
            }
    }
}

// MARK: - Floating Orb

private struct FloatingOrb: View {
    let index: Int
    let bounds: CGSize
    let color: Color
    let beatInterval: Double
    let isPlaying: Bool

    @State private var position: CGPoint = .zero
    @State private var orbScale: CGFloat = 1.0
    @State private var orbOpacity: Double = 0

    private var orbSize: CGFloat {
        CGFloat([30, 20, 45, 15, 35, 25][index % 6])
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: orbSize, height: orbSize)
            .blur(radius: orbSize * 0.4)
            .scaleEffect(orbScale)
            .opacity(orbOpacity)
            .position(position)
            .onAppear {
                position = randomPosition()
                orbOpacity = Double.random(in: 0.2...0.5)
            }
            .task {
                while !Task.isCancelled {
                    let duration = Double.random(in: 6...14)
                    withAnimation(.easeInOut(duration: duration)) {
                        position = randomPosition()
                    }
                    try? await Task.sleep(for: .seconds(duration))
                }
            }
            .task(id: isPlaying) {
                guard isPlaying else {
                    withAnimation(.easeOut(duration: 1)) { orbScale = 1.0 }
                    return
                }
                while !Task.isCancelled {
                    withAnimation(.easeOut(duration: beatInterval * 0.2)) {
                        orbScale = 1.3
                    }
                    try? await Task.sleep(for: .seconds(beatInterval * 0.2))
                    withAnimation(.easeIn(duration: beatInterval * 0.8)) {
                        orbScale = 1.0
                    }
                    try? await Task.sleep(for: .seconds(beatInterval * 0.8))
                }
            }
    }

    private func randomPosition() -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: bounds.width * 0.1...bounds.width * 0.9),
            y: CGFloat.random(in: bounds.height * 0.1...bounds.height * 0.9)
        )
    }
}
