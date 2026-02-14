import SwiftUI

/// Mountain social / browse nearby crews with FM dial metaphor.
struct DiscoveryView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var dialValue: Double = 0.5
    @State private var selectedSession: MockData.DiscoverySession?
    @State private var staticIntensity: Double = 0.1

    private var sessions: [MockData.DiscoverySession] { MockData.discoverySessions }

    private var highlightedIndex: Int {
        let idx = Int(dialValue * Double(sessions.count - 1))
        return max(0, min(sessions.count - 1, idx))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                VStack(spacing: 0) {
                    // FM Dial at top
                    dialSection

                    // Session list
                    sessionList
                }

                // CRT static between stations
                CRTStaticOverlay(intensity: staticIntensity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedSession) { session in
                sessionDetail(session)
            }
        }
    }

    // MARK: - Dial

    private var dialSection: some View {
        VStack(spacing: 8) {
            // Frequency display
            Text(sessions[highlightedIndex].frequency)
                .font(PirateTheme.display(28))
                .foregroundStyle(PirateTheme.signal)
                .neonGlow(PirateTheme.signal, intensity: 0.5)
                .contentTransition(.numericText())

            FrequencyDial(value: $dialValue, color: PirateTheme.signal)
                .frame(width: 140, height: 140)
                .onChange(of: dialValue) { _, _ in
                    // Flash static when tuning
                    withAnimation(.easeIn(duration: 0.1)) {
                        staticIntensity = 0.3
                    }
                    withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                        staticIntensity = 0.05
                    }
                }

            Text("tune to discover crews")
                .font(PirateTheme.body(11))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 16)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                sessionRow(session, isHighlighted: index == highlightedIndex)
                    .onTapGesture {
                        selectedSession = session
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func sessionRow(_ session: MockData.DiscoverySession, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            // Mini album art
            if let url = session.nowPlaying.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PirateTheme.signal.opacity(0.1))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.crewName)
                        .font(PirateTheme.display(14))
                        .foregroundStyle(isHighlighted ? PirateTheme.signal : .white)

                    Spacer()

                    Text(session.frequency)
                        .font(PirateTheme.body(11))
                        .foregroundStyle(PirateTheme.signal.opacity(0.6))
                }

                Text("\(session.nowPlaying.name) — \(session.nowPlaying.artist)")
                    .font(PirateTheme.body(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(session.memberCount)", systemImage: "person.2")
                    Label(session.distance, systemImage: "location")
                }
                .font(PirateTheme.body(10))
                .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            isHighlighted
                ? PirateTheme.signal.opacity(0.05)
                : Color.clear
        )
        .listRowSeparatorTint(PirateTheme.snow)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    // MARK: - Session Detail

    private func sessionDetail(_ session: MockData.DiscoverySession) -> some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Now playing
                    VinylArtView(
                        url: session.nowPlaying.albumArtURL,
                        isPlaying: true,
                        size: 160
                    )

                    Text(session.crewName)
                        .font(PirateTheme.display(22))
                        .foregroundStyle(.white)

                    Text(session.frequency)
                        .font(PirateTheme.display(16))
                        .foregroundStyle(PirateTheme.signal)

                    VStack(spacing: 4) {
                        Text(session.nowPlaying.name)
                            .font(PirateTheme.body(16))
                            .foregroundStyle(PirateTheme.signal)
                        Text(session.nowPlaying.artist)
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Members
                    HStack(spacing: -8) {
                        ForEach(session.members.prefix(6)) { member in
                            Circle()
                                .fill(member.avatarColor.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(String(member.displayName.prefix(1)).uppercased())
                                        .font(PirateTheme.display(12))
                                        .foregroundStyle(.white)
                                }
                                .overlay(Circle().strokeBorder(PirateTheme.void, lineWidth: 2))
                        }
                        if session.memberCount > 6 {
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text("+\(session.memberCount - 6)")
                                        .font(PirateTheme.body(10))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .overlay(Circle().strokeBorder(PirateTheme.void, lineWidth: 2))
                        }
                    }

                    Text("\(session.distance) away")
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.3))

                    Spacer()

                    // Tune In button
                    Button {
                        selectedSession = nil
                        // In demo: would navigate to NowPlaying as eavesdrop listener
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "radio")
                            Text("Tune In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .padding(.top, 32)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { selectedSession = nil }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

extension MockData.DiscoverySession: @retroactive Equatable {
    static func == (lhs: MockData.DiscoverySession, rhs: MockData.DiscoverySession) -> Bool {
        lhs.id == rhs.id
    }
}
