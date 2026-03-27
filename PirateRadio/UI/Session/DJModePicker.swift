import SwiftUI

/// 3-card DJ mode selector shown during session creation.
struct DJModePicker: View {
    @Binding var selectedMode: DJMode

    var body: some View {
        VStack(spacing: 16) {
            Text("CHOOSE YOUR STYLE")
                .font(PirateTheme.display(18))
                .foregroundStyle(PirateTheme.signal)

            ForEach(DJMode.allCases, id: \.self) { mode in
                modeCard(mode)
            }
        }
    }

    private func modeCard(_ mode: DJMode) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.system(size: 28))
                    .frame(width: 44)
                    .foregroundStyle(isSelected ? PirateTheme.broadcast : PirateTheme.signal)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .font(PirateTheme.display(16))
                        .foregroundStyle(isSelected ? PirateTheme.broadcast : .white)

                    Text(mode.description)
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PirateTheme.broadcast)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? PirateTheme.broadcast.opacity(0.1) : .white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? PirateTheme.broadcast : .white.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .neonGlow(PirateTheme.broadcast, intensity: isSelected ? 0.4 : 0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isSelected)
    }
}
