import SwiftUI

/// End-of-session stats card with animated counter build-up.
struct SessionRecapView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showHeader = false
    @State private var showTime = false
    @State private var showTracks = false
    @State private var showTopTrack = false
    @State private var showHighlights = false
    @State private var showLeaderboard = false

    @State private var animatedTime = 0
    @State private var animatedTracks = 0

    private let stats = MockData.sessionStats

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    if showHeader {
                        Text("SESSION COMPLETE")
                            .font(PirateTheme.display(28))
                            .foregroundStyle(PirateTheme.signal)
                            .neonGlow(PirateTheme.signal, intensity: 0.6)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Time + Tracks
                    if showTime {
                        HStack(spacing: 32) {
                            statBlock(value: formatTime(animatedTime), label: "Total Time")
                            if showTracks {
                                statBlock(value: "\(animatedTracks)", label: "Tracks Played")
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Top track
                    if showTopTrack {
                        topTrackCard
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Highlights
                    if showHighlights {
                        VStack(spacing: 12) {
                            highlightCard(icon: "music.note.list", label: "Most Requests",
                                          value: stats.mostRequests.name, detail: "\(stats.mostRequests.count) requests")
                            highlightCard(icon: "crown.fill", label: "Top DJ",
                                          value: stats.topDJ.name, detail: "\(stats.topDJ.minutes)m on the decks")
                            highlightCard(icon: "hand.thumbsup.fill", label: "Vote Machine",
                                          value: stats.voteMachine.name, detail: "\(stats.voteMachine.count) votes cast")
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // DJ Leaderboard
                    if showLeaderboard {
                        leaderboard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Actions
                    if showLeaderboard {
                        VStack(spacing: 16) {
                            ShareLink(
                                item: "Just finished a \(formatTime(stats.totalTimeMinutes)) Pirate Radio session! \(stats.tracksPlayed) tracks with the crew."
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share Recap")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))

                            Button {
                                dismiss()
                            } label: {
                                Text("Done")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GloveButtonStyle(color: .white.opacity(0.3)))
                        }
                        .padding(.top, 8)
                        .transition(.opacity)
                    }

                    // Watermark
                    if showLeaderboard {
                        Text("PIRATE RADIO")
                            .font(PirateTheme.display(12))
                            .foregroundStyle(.white.opacity(0.15))
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
        }
        .onAppear { startAnimation() }
    }

    // MARK: - Components

    private var topTrackCard: some View {
        HStack(spacing: 16) {
            if let url = stats.topTrack.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PirateTheme.signal.opacity(0.1))
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("TOP TRACK")
                    .font(PirateTheme.body(10))
                    .foregroundStyle(PirateTheme.flare.opacity(0.7))
                Text(stats.topTrack.name)
                    .font(PirateTheme.display(16))
                    .foregroundStyle(.white)
                Text(stats.topTrack.artist)
                    .font(PirateTheme.body(13))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(PirateTheme.flare.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func highlightCard(icon: String, label: String, value: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(PirateTheme.broadcast)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(PirateTheme.body(11))
                    .foregroundStyle(.white.opacity(0.4))
                HStack(spacing: 6) {
                    Text(value)
                        .font(PirateTheme.display(16))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(PirateTheme.broadcast.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DJ LEADERBOARD")
                .font(PirateTheme.body(11))
                .foregroundStyle(PirateTheme.broadcast.opacity(0.6))

            let maxMinutes = stats.djLeaderboard.first?.minutes ?? 1

            ForEach(Array(stats.djLeaderboard.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 12) {
                    Text("#\(index + 1)")
                        .font(PirateTheme.display(14))
                        .foregroundStyle(index == 0 ? PirateTheme.flare : .white.opacity(0.4))
                        .frame(width: 28)

                    Text(entry.name)
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white)
                        .frame(width: 100, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PirateTheme.broadcast.opacity(0.6))
                            .frame(
                                width: geo.size.width * CGFloat(entry.minutes) / CGFloat(maxMinutes),
                                height: 20
                            )
                    }
                    .frame(height: 20)

                    Text("\(entry.minutes)m")
                        .font(PirateTheme.body(11))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(PirateTheme.broadcast.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(PirateTheme.display(32))
                .foregroundStyle(PirateTheme.signal)
                .monospacedDigit()
            Text(label)
                .font(PirateTheme.body(12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Animation Sequence

    private func startAnimation() {
        Task {
            // Header
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(duration: 0.5)) { showHeader = true }

            // Time counter
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.spring(duration: 0.4)) { showTime = true }
            await animateCounter(to: stats.totalTimeMinutes, binding: $animatedTime, duration: 0.8)

            // Tracks counter
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(duration: 0.4)) { showTracks = true }
            await animateCounter(to: stats.tracksPlayed, binding: $animatedTracks, duration: 0.6)

            // Top track
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.spring(duration: 0.5)) { showTopTrack = true }

            // Highlights
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.spring(duration: 0.5)) { showHighlights = true }

            // Leaderboard
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.spring(duration: 0.5)) { showLeaderboard = true }
        }
    }

    private func animateCounter(to target: Int, binding: Binding<Int>, duration: Double) async {
        let steps = 20
        let stepDelay = duration / Double(steps)
        for i in 1...steps {
            try? await Task.sleep(for: .seconds(stepDelay))
            let value = Int(Double(target) * Double(i) / Double(steps))
            withAnimation(.none) {
                binding.wrappedValue = value
            }
        }
    }

    private func formatTime(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
