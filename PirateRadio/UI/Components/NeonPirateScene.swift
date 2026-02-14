import SwiftUI

/// A tiny neon-outlined pirate ship sailing between mountains.
struct NeonPirateScene: View {
    var color: Color = PirateTheme.signal

    @State private var shipX: CGFloat = -0.1
    @State private var bobPhase: Bool = false
    @State private var sailPulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Mountains behind
                mountains(w: w, h: h)

                // Water line
                waterLine(w: w, h: h)

                // Ship sailing across
                pirateShip
                    .frame(width: 38, height: 32)
                    .offset(y: bobPhase ? -2 : 2)
                    .position(
                        x: shipX * w,
                        y: h * 0.58
                    )
            }
        }
        .frame(height: 50)
        .clipped()
        .task {
            // Bob up and down
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bobPhase = true
            }
            // Sail pulse
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                sailPulse = true
            }
            // Sail across
            while !Task.isCancelled {
                shipX = -0.05
                withAnimation(.linear(duration: 18)) {
                    shipX = 1.05
                }
                try? await Task.sleep(for: .seconds(18))
            }
        }
    }

    // MARK: - Mountains

    private func mountains(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // Back range (dimmer)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.7))
                p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.25))
                p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.15))
                p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.3))
                p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.45))
                p.addLine(to: CGPoint(x: w, y: h * 0.7))
                p.closeSubpath()
            }
            .fill(color.opacity(0.03))
            .stroke(color.opacity(0.12), lineWidth: 0.5)

            // Front range (slightly brighter)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.7))
                p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.45))
                p.addLine(to: CGPoint(x: w * 0.18, y: h * 0.6))
                p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.35))
                p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.6))
                p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.4))
                p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.6))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.38))
                p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.58))
                p.addLine(to: CGPoint(x: w, y: h * 0.7))
                p.closeSubpath()
            }
            .fill(color.opacity(0.04))
            .stroke(color.opacity(0.18), lineWidth: 0.5)
        }
    }

    // MARK: - Water Line

    private func waterLine(w: CGFloat, h: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.65))
            // Wavy water
            let segments = 12
            for i in 0...segments {
                let x = w * CGFloat(i) / CGFloat(segments)
                let waveY = h * 0.65 + sin(CGFloat(i) * .pi * 0.8) * 3
                if i == 0 {
                    p.move(to: CGPoint(x: x, y: waveY))
                } else {
                    let cpX = w * (CGFloat(i) - 0.5) / CGFloat(segments)
                    let cpY = h * 0.65 - sin(CGFloat(i) * .pi * 0.8 + 0.4) * 3
                    p.addQuadCurve(to: CGPoint(x: x, y: waveY),
                                   control: CGPoint(x: cpX, y: cpY))
                }
            }
        }
        .stroke(color.opacity(0.2), lineWidth: 0.5)
    }

    // MARK: - Pirate Ship

    private var pirateShip: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let c = color

            // Hull
            var hull = Path()
            hull.move(to: CGPoint(x: w * 0.1, y: h * 0.6))
            hull.addLine(to: CGPoint(x: w * 0.15, y: h * 0.85))
            hull.addQuadCurve(
                to: CGPoint(x: w * 0.85, y: h * 0.85),
                control: CGPoint(x: w * 0.5, y: h * 0.95))
            hull.addLine(to: CGPoint(x: w * 0.9, y: h * 0.6))
            hull.closeSubpath()
            ctx.stroke(hull, with: .color(c), lineWidth: 1)

            // Bowsprit
            var bowsprit = Path()
            bowsprit.move(to: CGPoint(x: w * 0.88, y: h * 0.6))
            bowsprit.addLine(to: CGPoint(x: w * 1.0, y: h * 0.48))
            ctx.stroke(bowsprit, with: .color(c.opacity(0.6)), lineWidth: 0.8)

            // Mast
            var mast = Path()
            mast.move(to: CGPoint(x: w * 0.5, y: h * 0.6))
            mast.addLine(to: CGPoint(x: w * 0.5, y: h * 0.05))
            ctx.stroke(mast, with: .color(c.opacity(0.5)), lineWidth: 0.8)

            // Main sail
            var sail = Path()
            sail.move(to: CGPoint(x: w * 0.52, y: h * 0.1))
            sail.addQuadCurve(
                to: CGPoint(x: w * 0.52, y: h * 0.5),
                control: CGPoint(x: w * 0.78, y: h * 0.28))
            sail.addLine(to: CGPoint(x: w * 0.52, y: h * 0.1))
            let sailAlpha = sailPulse ? 0.2 : 0.1
            ctx.fill(sail, with: .color(c.opacity(sailAlpha)))
            ctx.stroke(sail, with: .color(c.opacity(0.5)), lineWidth: 0.8)

            // Flag at top
            var flag = Path()
            flag.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
            flag.addLine(to: CGPoint(x: w * 0.62, y: h * 0.08))
            flag.addLine(to: CGPoint(x: w * 0.5, y: h * 0.12))
            ctx.fill(flag, with: .color(c.opacity(0.4)))

            // Skull on sail (tiny dot + crossbones hint)
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
