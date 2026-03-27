import SwiftUI

/// A rotary dial control with neon styling, tick marks, and haptic detents.
/// Used for volume control, session join, and as the dial home screen.
///
/// When `stations` is provided, the dial operates in station mode:
/// detents are derived from station frequencies, tick marks glow for live stations,
/// and the center shows the snapped station's name instead of a numeric value.
struct FrequencyDial: View {
    @Binding var value: Double // 0.0 to 1.0
    let color: Color
    var detents: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    var onDetentSnap: ((Double) -> Void)?

    // Station mode — when non-empty, dial derives detents from station frequencies
    var stations: [Station] = []
    var onTuneToStation: ((Station) -> Void)?

    @State private var dragAngle: Angle = .zero
    @State private var lastDetent: Double = -1
    @GestureState private var isDragging = false

    // Dial geometry
    private let startAngle: Double = -135 // degrees
    private let endAngle: Double = 135
    private let tickCount = 20

    // FM band range for frequency-to-dial mapping
    private let fmMin: Double = 88.0
    private let fmMax: Double = 108.0

    /// Detents used for rendering — derived from stations when in station mode.
    private var effectiveDetents: [Double] {
        if stations.isEmpty { return detents }
        return stations.map { frequencyToDialValue($0.frequency) }
    }

    /// The station closest to the current dial position (if in station mode).
    private var snappedStation: Station? {
        guard !stations.isEmpty else { return nil }
        let dialValue = value
        var closest: Station?
        var closestDist = Double.infinity
        for station in stations {
            let stationValue = frequencyToDialValue(station.frequency)
            let dist = abs(dialValue - stationValue)
            if dist < closestDist && dist < 0.08 {
                closestDist = dist
                closest = station
            }
        }
        return closest
    }

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
                    let isMajor = effectiveDetents.contains(where: { abs($0 - fraction) < 0.03 })

                    tickMark(angle: angle, radius: radius, isMajor: isMajor, isActive: isActive)
                }

                // Station notch markers (glow dots at each station's position)
                if !stations.isEmpty {
                    ForEach(stations) { station in
                        let dialPos = frequencyToDialValue(station.frequency)
                        let angle = Angle.degrees(startAngle + dialPos * (endAngle - startAngle))
                        stationNotch(angle: angle, radius: radius, station: station, size: size)
                    }
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

                // Center label — station name or frequency value
                centerLabel(size: size)
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

                        checkDetentSnap(clamped)
                    }
            )
            .neonGlow(color, intensity: isDragging ? 0.8 : 0.3)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func centerLabel(size: CGFloat) -> some View {
        if let station = snappedStation {
            VStack(spacing: 2) {
                Text(station.displayName)
                    .font(PirateTheme.display(size * 0.08))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(String(format: "%.1f", station.frequency))
                    .font(PirateTheme.body(size * 0.06))
                    .foregroundStyle(color.opacity(0.7))
            }
            .frame(width: size * 0.25)
        } else if !stations.isEmpty {
            Text("SCAN")
                .font(PirateTheme.display(size * 0.08))
                .foregroundStyle(color.opacity(0.5))
        } else {
            Text(String(format: "%.0f", value * 100))
                .font(PirateTheme.display(size * 0.12))
                .foregroundStyle(color)
        }
    }

    private func stationNotch(angle: Angle, radius: CGFloat, station: Station, size: CGFloat) -> some View {
        let notchRadius = radius - 30
        let cos = Foundation.cos(angle.radians)
        let sin = Foundation.sin(angle.radians)
        let x = radius + notchRadius * cos
        let y = radius + notchRadius * sin

        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color, radius: 4)
            .position(x: x, y: y)
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

    // MARK: - Helpers

    private func checkDetentSnap(_ value: Double) {
        for detent in effectiveDetents {
            if abs(value - detent) < 0.05 && lastDetent != detent {
                lastDetent = detent
                onDetentSnap?(detent)

                // In station mode, also fire onTuneToStation
                if !stations.isEmpty {
                    if let station = stations.first(where: { abs(frequencyToDialValue($0.frequency) - detent) < 0.01 }) {
                        onTuneToStation?(station)
                    }
                }
            }
        }
    }

    private func frequencyToDialValue(_ frequency: Double) -> Double {
        (frequency - fmMin) / (fmMax - fmMin)
    }
}
