import SwiftUI

/// A tiny neon-outlined pirate fleet sailing between mountains.
/// One ship per crew member, each with a random time offset and slightly different speed.
/// The DJ's ship is larger — it's the flagship.
struct NeonPirateScene: View {
    var color: Color = PirateTheme.signal
    var members: [Session.Member] = []
    var djUserID: UserID = ""

    @State private var bobPhase: Bool = false
    @State private var sailPulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                mountains(w: w, h: h)
                waterLine(w: w, h: h)

                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    let isDJ = member.id == djUserID
                    let nonDJIndex = members.filter { $0.id != djUserID }.firstIndex(where: { $0.id == member.id })
                    let nonDJCount = max(members.filter { $0.id != djUserID }.count, 1)
                    SailingShip(
                        color: member.avatarColor.color,
                        cycleOffset: isDJ ? 0 : spacedOffset(index: nonDJIndex ?? 0, total: nonDJCount, id: member.id),
                        cycleDuration: stableSpeed(for: member.id),
                        sceneWidth: w,
                        bobPhase: bobPhase,
                        sailPulse: sailPulse,
                        immediate: isDJ
                    )
                    .frame(width: isDJ ? 52 : 38, height: isDJ ? 44 : 32)
                    .position(x: w * 0.5, y: h * (isDJ ? 0.64 : 0.68))
                }
            }
        }
        .frame(height: 70)
        .clipped()
        .task {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bobPhase = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                sailPulse = true
            }
        }
    }

    /// Evenly space ships across the cycle, with a small deterministic jitter per ship.
    private func spacedOffset(index: Int, total: Int, id: String) -> Double {
        let evenSpacing = Double(index + 1) / Double(total + 1) // e.g. 1/4, 2/4, 3/4 for 3 ships
        let hash = id.utf8.reduce(0) { ($0 &+ UInt64($1)) &* 31 }
        let jitter = (Double(hash % 100) / 100.0 - 0.5) * 0.08 // ±4% wobble
        return (evenSpacing + jitter).clamped(to: 0.05...0.95)
    }

    /// Deterministic speed (14...22s) so each ship sails at a slightly different pace.
    private func stableSpeed(for id: String) -> Double {
        let hash = id.utf8.reduce(0) { ($0 &+ UInt64($1)) &* 37 }
        return 14.0 + Double(hash % 800) / 100.0  // 14...22 seconds
    }

    // MARK: - Mountains

    private func mountains(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Back range — tall peaks
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.75))
                p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.10))
                p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.45))
                p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.05))
                p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.40))
                p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.15))
                p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.42))
                p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.08))
                p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.35))
                p.addLine(to: CGPoint(x: w, y: h * 0.75))
                p.closeSubpath()
            }
            .fill(color.opacity(0.03))
            .stroke(color.opacity(0.12), lineWidth: 0.5)

            // Front range — slightly shorter but still prominent
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.75))
                p.addLine(to: CGPoint(x: w * 0.07, y: h * 0.30))
                p.addLine(to: CGPoint(x: w * 0.16, y: h * 0.50))
                p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.18))
                p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.48))
                p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.25))
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.50))
                p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.22))
                p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.48))
                p.addLine(to: CGPoint(x: w, y: h * 0.75))
                p.closeSubpath()
            }
            .fill(color.opacity(0.04))
            .stroke(color.opacity(0.18), lineWidth: 0.5)
        }
    }

    // MARK: - Water Line

    private func waterLine(w: CGFloat, h: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.72))
            let segments = 12
            for i in 0...segments {
                let x = w * CGFloat(i) / CGFloat(segments)
                let waveY = h * 0.72 + sin(CGFloat(i) * .pi * 0.8) * 3
                if i == 0 {
                    p.move(to: CGPoint(x: x, y: waveY))
                } else {
                    let cpX = w * (CGFloat(i) - 0.5) / CGFloat(segments)
                    let cpY = h * 0.72 - sin(CGFloat(i) * .pi * 0.8 + 0.4) * 3
                    p.addQuadCurve(to: CGPoint(x: x, y: waveY),
                                   control: CGPoint(x: cpX, y: cpY))
                }
            }
        }
        .stroke(color.opacity(0.2), lineWidth: 0.5)
    }
}

// MARK: - Individual Sailing Ship

/// A single ship that sails across on a cycle, offset by `cycleOffset`.
private struct SailingShip: View {
    let color: Color
    let cycleOffset: Double   // 0...1 — where in the cycle this ship starts
    let cycleDuration: Double // seconds for one crossing
    let sceneWidth: CGFloat
    let bobPhase: Bool
    let sailPulse: Bool
    var immediate: Bool = false

    @State private var shipX: CGFloat = -0.05
    @State private var appeared = false

    var body: some View {
        pirateShipCanvas
            .offset(
                x: (shipX - 0.5) * sceneWidth,
                y: bobPhase ? -2 : 2
            )
            .opacity(appeared ? 1 : 0)
            .task {
                if immediate {
                    appeared = true
                } else {
                    let initialDelay = cycleOffset * cycleDuration
                    try? await Task.sleep(for: .seconds(initialDelay))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.5)) { appeared = true }
                }

                while !Task.isCancelled {
                    shipX = -0.05
                    withAnimation(.linear(duration: cycleDuration)) {
                        shipX = 1.05
                    }
                    try? await Task.sleep(for: .seconds(cycleDuration))
                }
            }
    }

    private var pirateShipCanvas: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let c = color

            var hull = Path()
            hull.move(to: CGPoint(x: w * 0.1, y: h * 0.6))
            hull.addLine(to: CGPoint(x: w * 0.15, y: h * 0.85))
            hull.addQuadCurve(
                to: CGPoint(x: w * 0.85, y: h * 0.85),
                control: CGPoint(x: w * 0.5, y: h * 0.95))
            hull.addLine(to: CGPoint(x: w * 0.9, y: h * 0.6))
            hull.closeSubpath()
            ctx.stroke(hull, with: .color(c), lineWidth: 1)

            var bowsprit = Path()
            bowsprit.move(to: CGPoint(x: w * 0.88, y: h * 0.6))
            bowsprit.addLine(to: CGPoint(x: w * 1.0, y: h * 0.48))
            ctx.stroke(bowsprit, with: .color(c.opacity(0.6)), lineWidth: 0.8)

            var mast = Path()
            mast.move(to: CGPoint(x: w * 0.5, y: h * 0.6))
            mast.addLine(to: CGPoint(x: w * 0.5, y: h * 0.05))
            ctx.stroke(mast, with: .color(c.opacity(0.5)), lineWidth: 0.8)

            var sail = Path()
            sail.move(to: CGPoint(x: w * 0.52, y: h * 0.1))
            sail.addQuadCurve(
                to: CGPoint(x: w * 0.52, y: h * 0.5),
                control: CGPoint(x: w * 0.78, y: h * 0.28))
            sail.addLine(to: CGPoint(x: w * 0.52, y: h * 0.1))
            let sailAlpha = sailPulse ? 0.2 : 0.1
            ctx.fill(sail, with: .color(c.opacity(sailAlpha)))
            ctx.stroke(sail, with: .color(c.opacity(0.5)), lineWidth: 0.8)

            var flag = Path()
            flag.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
            flag.addLine(to: CGPoint(x: w * 0.62, y: h * 0.08))
            flag.addLine(to: CGPoint(x: w * 0.5, y: h * 0.12))
            ctx.fill(flag, with: .color(c.opacity(0.4)))

            let skullCenter = CGPoint(x: w * 0.58, y: h * 0.3)
            let skullR: CGFloat = 2
            ctx.fill(Path(ellipseIn: CGRect(
                x: skullCenter.x - skullR,
                y: skullCenter.y - skullR,
                width: skullR * 2, height: skullR * 2
            )), with: .color(c.opacity(0.4)))
        }
        .shadow(color: color.opacity(sailPulse ? 0.5 : 0.2), radius: 4)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
