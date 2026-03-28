import SwiftUI

/// A rotary dial that snaps between station detents.
///
/// In station mode the dial only stops at station positions — dragging
/// anywhere snaps to the nearest station. The selected station index
/// is exposed via `selectedIndex` so the parent can show a "Tune In" button.
struct FrequencyDial: View {
    let color: Color
    var stations: [Station] = []
    @Binding var selectedIndex: Int

    @GestureState private var isDragging = false

    // Dial geometry
    private let startAngle: Double = -135 // degrees
    private let endAngle: Double = 135
    private let tickCount = 20

    // FM band range for frequency-to-dial mapping
    static let fmMin: Double = 88.0
    static let fmMax: Double = 108.0

    /// The dial value (0–1) for the currently selected station.
    private var dialValue: Double {
        guard !stations.isEmpty else { return 0.5 }
        let idx = min(max(selectedIndex, 0), stations.count - 1)
        return frequencyToDialValue(stations[idx].frequency)
    }

    /// The currently selected station (always valid when stations are present).
    var selectedStation: Station? {
        guard !stations.isEmpty else { return nil }
        return stations[min(max(selectedIndex, 0), stations.count - 1)]
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
                    let isActive = fraction <= dialValue
                    let isStation = stations.contains(where: { abs(frequencyToDialValue($0.frequency) - fraction) < 0.03 })

                    tickMark(angle: angle, radius: radius, isMajor: isStation, isActive: isActive)
                }

                // Station notch markers (glow dots)
                ForEach(Array(stations.enumerated()), id: \.element.id) { idx, station in
                    let dialPos = frequencyToDialValue(station.frequency)
                    let angle = Angle.degrees(startAngle + dialPos * (endAngle - startAngle))
                    let isSelected = idx == selectedIndex
                    stationNotch(angle: angle, radius: radius, isSelected: isSelected, size: size)
                }

                // Indicator line
                let indicatorAngle = Angle.degrees(startAngle + dialValue * (endAngle - startAngle))
                indicatorLine(angle: indicatorAngle, radius: radius)

                // Center knob
                Circle()
                    .fill(PirateTheme.void)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(0.5), lineWidth: 1)
                    )

                // Center label — always shows a station
                centerLabel(size: size)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { drag in
                        guard !stations.isEmpty else { return }
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let angle = atan2(drag.location.y - center.y, drag.location.x - center.x)
                        let degrees = angle * 180 / .pi
                        let normalized = (degrees - startAngle) / (endAngle - startAngle)
                        let clamped = max(0, min(1, normalized))

                        // Snap to nearest station
                        let nearest = nearestStationIndex(for: clamped)
                        if nearest != selectedIndex {
                            selectedIndex = nearest
                        }
                    }
            )
            .neonGlow(color, intensity: isDragging ? 0.8 : 0.3)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func centerLabel(size: CGFloat) -> some View {
        if let station = selectedStation {
            VStack(spacing: 1) {
                Text(station.name)
                    .font(PirateTheme.display(size * 0.1))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if station.listenerCount > 0 {
                    Text("\(station.listenerCount) listening")
                        .font(PirateTheme.body(size * 0.045))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: size * 0.35)
        } else {
            Text("NO SIGNAL")
                .font(PirateTheme.display(size * 0.07))
                .foregroundStyle(color.opacity(0.3))
        }
    }

    private func stationNotch(angle: Angle, radius: CGFloat, isSelected: Bool, size: CGFloat) -> some View {
        let notchRadius = radius - 28
        let cos = Foundation.cos(angle.radians)
        let sin = Foundation.sin(angle.radians)
        let x = radius + notchRadius * cos
        let y = radius + notchRadius * sin
        let dotSize: CGFloat = isSelected ? 10 : 6

        return Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .shadow(color: color, radius: isSelected ? 8 : 4)
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

    private func nearestStationIndex(for dialVal: Double) -> Int {
        var bestIdx = 0
        var bestDist = Double.infinity
        for (i, station) in stations.enumerated() {
            let dist = abs(frequencyToDialValue(station.frequency) - dialVal)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    private func frequencyToDialValue(_ frequency: Double) -> Double {
        (frequency - Self.fmMin) / (Self.fmMax - Self.fmMin)
    }
}
