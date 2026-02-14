import SwiftUI

/// A rotary dial control with neon styling, tick marks, and haptic detents.
/// Used for volume control and as the hero "tuning" interaction for session join.
struct FrequencyDial: View {
    @Binding var value: Double // 0.0 to 1.0
    let color: Color
    var detents: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    var onDetentSnap: ((Double) -> Void)?

    @State private var dragAngle: Angle = .zero
    @State private var lastDetent: Double = -1
    @GestureState private var isDragging = false

    // Dial geometry
    private let startAngle: Double = -135 // degrees
    private let endAngle: Double = 135
    private let tickCount = 20

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2

            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(color.opacity(0.3), lineWidth: 2)

                // Tick marks
                ForEach(0..<tickCount, id: \.self) { i in
                    let fraction = Double(i) / Double(tickCount - 1)
                    let angle = Angle.degrees(startAngle + fraction * (endAngle - startAngle))
                    let isActive = fraction <= value
                    let isMajor = detents.contains(where: { abs($0 - fraction) < 0.03 })

                    tickMark(angle: angle, radius: radius, isMajor: isMajor, isActive: isActive)
                }

                // Indicator line
                let indicatorAngle = Angle.degrees(startAngle + value * (endAngle - startAngle))
                indicatorLine(angle: indicatorAngle, radius: radius)

                // Center knob
                Circle()
                    .fill(PirateTheme.void)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(0.5), lineWidth: 1)
                    )

                // Value label
                Text(String(format: "%.0f", value * 100))
                    .font(PirateTheme.display(size * 0.12))
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let angle = atan2(drag.location.y - center.y, drag.location.x - center.x)
                        let degrees = angle * 180 / .pi

                        // Map angle to value
                        let normalized = (degrees - startAngle) / (endAngle - startAngle)
                        let clamped = max(0, min(1, normalized))
                        value = clamped

                        // Snap to detents with haptic
                        checkDetentSnap(clamped)
                    }
            )
            .neonGlow(color, intensity: isDragging ? 0.8 : 0.3)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func tickMark(angle: Angle, radius: CGFloat, isMajor: Bool, isActive: Bool) -> some View {
        let length: CGFloat = isMajor ? 12 : 6
        let innerRadius = radius - 20
        let outerRadius = innerRadius + length

        return Path { path in
            let cos = Foundation.cos(angle.radians)
            let sin = Foundation.sin(angle.radians)
            path.move(to: CGPoint(
                x: radius + innerRadius * cos,
                y: radius + innerRadius * sin
            ))
            path.addLine(to: CGPoint(
                x: radius + outerRadius * cos,
                y: radius + outerRadius * sin
            ))
        }
        .stroke(
            isActive ? color : color.opacity(0.2),
            lineWidth: isMajor ? 2 : 1
        )
    }

    private func indicatorLine(angle: Angle, radius: CGFloat) -> some View {
        let innerRadius = radius * 0.2
        let outerRadius = radius * 0.65

        return Path { path in
            let cos = Foundation.cos(angle.radians)
            let sin = Foundation.sin(angle.radians)
            path.move(to: CGPoint(
                x: radius + innerRadius * cos,
                y: radius + innerRadius * sin
            ))
            path.addLine(to: CGPoint(
                x: radius + outerRadius * cos,
                y: radius + outerRadius * sin
            ))
        }
        .stroke(color, lineWidth: 3)
        .shadow(color: color.opacity(0.8), radius: 4)
    }

    private func checkDetentSnap(_ value: Double) {
        for detent in detents {
            if abs(value - detent) < 0.05 && lastDetent != detent {
                lastDetent = detent
                onDetentSnap?(detent)
            }
        }
    }
}
