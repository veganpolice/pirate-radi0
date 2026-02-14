import SwiftUI

/// The main now-playing screen shown during an active session.
/// Album art, track info, progress bar, controls, crew strip,
/// hot-seat banner, BPM gauge, walkie-talkie, and signal lost overlay.
struct NowPlayingView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    @State private var volume: Double = 0.5
    @State private var showQueue = false
    @State private var showRequests = false
    @State private var showSettings = false
    @State private var showMemberProfile: Session.Member?
    @State private var showSignalLost = false
    @State private var chairliftMode = false

    // Staggered entrance
    @State private var showArt = false
    @State private var showTitle = false
    @State private var showProgress = false
    @State private var showControls = false
    @State private var showCrew = false

    // Request badge count
    @State private var pendingRequestCount = 5

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            // Pulsing beat background — behind all UI
            BeatPulseBackground(isPlaying: sessionStore.session?.isPlaying ?? false)

            if chairliftMode {
                ChairliftModeView()
            } else {
                mainContent
            }

            // Signal lost overlay
            SignalLostOverlay(isActive: $showSignalLost)

            // Walkie-talkie (bottom-right floating)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    WalkieTalkieButton()
                        .padding(.trailing, 16)
                        .padding(.bottom, 100)
                }
            }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showRequests) { RequestsView() }
        .sheet(isPresented: $showSettings) { SessionSettingsView() }
        .sheet(item: $showMemberProfile) { member in
            MemberProfileCard(member: member)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .onAppear { startEntranceAnimation() }
        .onShake { handleShake() }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top bar: BPM gauge + gear icon
            topBar

            // Hot-seat banner
            HotSeatBanner()

            // Album art + track info
            if showArt {
                trackHeader
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Progress bar
            if showProgress, let track = sessionStore.session?.currentTrack {
                TrackProgressBar(
                    durationMs: track.durationMs,
                    isPlaying: sessionStore.session?.isPlaying ?? false,
                    isDJ: sessionStore.isDJ
                ) { seekPos in
                    Task { await sessionStore.seek(to: seekPos) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .transition(.opacity)
            }

            Spacer()

            // Crew strip
            if showCrew {
                crewStrip
                    .padding(.vertical, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Controls
            if showControls {
                Group {
                    if sessionStore.isDJ {
                        djControls
                    } else {
                        listenerControls
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            // Volume dial
            FrequencyDial(value: $volume, color: PirateTheme.signal)
                .frame(width: 120, height: 120)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // BPM Gauge
            BPMGauge(isPlaying: sessionStore.session?.isPlaying ?? false)
                .frame(width: 80, height: 48)

            Spacer()

            // Request badge (DJ only, solo mode)
            if sessionStore.isDJ && sessionStore.session?.djMode == .solo {
                Button { showRequests = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "tray.full")
                            .font(.title3)
                            .foregroundStyle(PirateTheme.signal)

                        if pendingRequestCount > 0 {
                            Text("\(pendingRequestCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(.red))
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
            }

            // Settings gear
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(PirateTheme.signal.opacity(0.6))
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.top, 8)
    }

    // MARK: - Track Header

    private var trackHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            // Album art with breathing animation
            VinylArtView(
                url: sessionStore.session?.currentTrack?.albumArtURL,
                isPlaying: sessionStore.session?.isPlaying ?? false
            )

            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
            // Track title overlapping art
            if let track = sessionStore.session?.currentTrack {
                VStack(alignment: .trailing, spacing: 4) {
                    if showTitle {
                        Text(track.name)
                            .font(PirateTheme.display(20))
                            .foregroundStyle(PirateTheme.signal)
                            .neonGlow(PirateTheme.signal, intensity: 0.5)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))

                        Text(track.artist)
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Crew Strip

    private var crewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let session = sessionStore.session {
                    ForEach(session.members) { member in
                        Button {
                            showMemberProfile = member
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(member.avatarColor.color.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                member.id == session.djUserID ? PirateTheme.broadcast : member.avatarColor.color,
                                                lineWidth: 2
                                            )
                                    )
                                    .overlay {
                                        Text(String(member.displayName.prefix(1)).uppercased())
                                            .font(PirateTheme.display(16))
                                            .foregroundStyle(member.avatarColor.color)
                                    }

                                Text(member.displayName)
                                    .font(PirateTheme.body(10))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 8)
            .animation(.spring(duration: 0.4), value: sessionStore.session?.members.map(\.id))
        }
    }

    // MARK: - DJ Controls

    private var djControls: some View {
        HStack(spacing: 24) {
            // Previous / Seek back
            Button {
                Task { await sessionStore.seek(to: 0) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)
            .sensoryFeedback(.impact(weight: .light), trigger: UUID())

            // Play / Pause
            Button {
                Task {
                    if sessionStore.session?.isPlaying == true {
                        await sessionStore.pause()
                    } else {
                        await sessionStore.resume()
                    }
                }
            } label: {
                Image(systemName: sessionStore.session?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))

            // Skip
            Button {
                sessionStore.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)
            .sensoryFeedback(.impact(weight: .light), trigger: UUID())

            // Queue
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)
        }
        .foregroundStyle(PirateTheme.broadcast)
        .padding(.vertical, 8)
    }

    // MARK: - Listener Controls

    private var listenerControls: some View {
        HStack(spacing: 16) {
            // Sync status
            ConnectionStatusBadge(state: sessionStore.connectionState)

            Spacer()

            // Request song
            Button { showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Request Song")
                }
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Entrance Animation

    private func startEntranceAnimation() {
        withAnimation(.spring(duration: 0.5)) { showArt = true }
        withAnimation(.spring(duration: 0.5).delay(0.2)) { showTitle = true }
        withAnimation(.spring(duration: 0.5).delay(0.4)) { showProgress = true }
        withAnimation(.spring(duration: 0.5).delay(0.6)) { showControls = true }
        withAnimation(.spring(duration: 0.5).delay(0.8)) { showCrew = true }
    }

    // MARK: - Debug Shake

    private func handleShake() {
        let actions: [() -> Void] = [
            { showSignalLost = true },
            {
                toastManager.show(.memberJoined, message: "Gondola Greg joined the session")
                if let greg = MockData.members.first(where: { $0.displayName == "Gondola Greg" }) {
                    sessionStore.addMember(greg)
                }
            },
            {
                toastManager.show(.songRequest, message: "Shredder requested \"Midnight City\"")
            },
            {
                toastManager.show(.djChanged, message: "Shredder is now DJ")
            },
        ]
        actions.randomElement()?()
    }
}

// MARK: - Shake Gesture

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(onShake: action))
    }
}

struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                onShake()
            }
    }
}

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}
