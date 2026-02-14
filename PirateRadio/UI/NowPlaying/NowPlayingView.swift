import SwiftUI

/// The main now-playing screen shown during an active session.
/// Album art, track info, progress bar, controls, crew strip,
/// hot-seat banner, walkie-talkie megaphone, and bottom menu bar.
struct NowPlayingView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    @State private var showQueue = false
    @State private var showRequests = false
    @State private var showSettings = false
    @State private var showMemberProfile: Session.Member?
    @State private var showSignalLost = false
    @State private var chairliftMode = false

    @State private var isMuted = false

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
            BeatPulseBackground(
                isPlaying: sessionStore.session?.isPlaying ?? false,
                members: sessionStore.session?.members ?? [],
                djUserID: sessionStore.session?.djUserID ?? ""
            )

            if chairliftMode {
                ChairliftModeView()
            } else {
                mainContent
            }

            // Signal lost overlay
            SignalLostOverlay(isActive: $showSignalLost)
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

            // Neon pirate fleet sailing between mountains
            NeonPirateScene(
                color: PirateTheme.signal,
                members: sessionStore.session?.members ?? [],
                djUserID: sessionStore.session?.djUserID ?? ""
            )
            .padding(.horizontal, 8)

            Spacer()

            // Crew strip
            if showCrew {
                crewStrip
                    .padding(.vertical, 12)
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

            // Bottom menu bar
            bottomBar
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Hamburger menu
            Button { showSettings = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                    Text("Menu")
                        .font(PirateTheme.body(9))
                }
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 50)

            // Messages / Requests
            Button { showRequests = true } label: {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 3) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 20, weight: .medium))
                        Text("Messages")
                            .font(PirateTheme.body(9))
                    }

                    if pendingRequestCount > 0 {
                        Text("\(pendingRequestCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(.red))
                            .offset(x: 8, y: -4)
                    }
                }
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 50)

            // Megaphone (walkie-talkie) — bigger, central
            MegaphoneButton()
                .frame(maxWidth: .infinity, minHeight: 50)

            // Queue
            Button { showQueue = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .medium))
                    Text("Queue")
                        .font(PirateTheme.body(9))
                }
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 50)

            // Settings gear
            Button { showSettings = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                    Text("Settings")
                        .font(PirateTheme.body(9))
                }
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(PirateTheme.void.opacity(0.8))
                .blur(radius: 8)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Track Header

    private var trackHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            VinylArtView(
                url: sessionStore.session?.currentTrack?.albumArtURL,
                isPlaying: sessionStore.session?.isPlaying ?? false
            )

            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
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
        HStack(spacing: 20) {
            // Seek back
            Button {
                Task { await sessionStore.seek(to: 0) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 52, minHeight: 52)
            .sensoryFeedback(.impact(weight: .light), trigger: UUID())

            // Mute / Unmute (main button)
            Button {
                withAnimation(.spring(duration: 0.2)) { isMuted.toggle() }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.largeTitle)
            }
            .buttonStyle(GloveButtonStyle(color: isMuted ? PirateTheme.flare : PirateTheme.broadcast))
            .sensoryFeedback(.impact(weight: .medium), trigger: isMuted)

            // Pause-for-all (smaller, exclamation mark)
            Button {
                Task {
                    if sessionStore.session?.isPlaying == true {
                        await sessionStore.pause()
                    } else {
                        await sessionStore.resume()
                    }
                }
            } label: {
                Image(systemName: sessionStore.session?.isPlaying == true
                      ? "exclamationmark.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .frame(minWidth: 44, minHeight: 44)
            .sensoryFeedback(.impact(weight: .light), trigger: UUID())

            // Skip
            Button {
                sessionStore.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 52, minHeight: 52)
            .sensoryFeedback(.impact(weight: .light), trigger: UUID())
        }
        .foregroundStyle(PirateTheme.broadcast)
        .padding(.vertical, 8)
    }

    // MARK: - Listener Controls

    private var listenerControls: some View {
        HStack(spacing: 16) {
            ConnectionStatusBadge(state: sessionStore.connectionState)

            Spacer()

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

// MARK: - Megaphone Button

/// Large megaphone-style push-to-talk button for the bottom bar.
struct MegaphoneButton: View {
    @Environment(ToastManager.self) private var toastManager

    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var waveformLevels: [CGFloat] = Array(repeating: 0.2, count: 5)

    private let maxRecordingSeconds: Double = 10

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(isRecording ? PirateTheme.flare.opacity(0.15) : Color.clear)
                    .frame(width: 64, height: 64)

                // Main button
                Circle()
                    .fill(PirateTheme.void)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .strokeBorder(PirateTheme.flare, lineWidth: isRecording ? 3 : 1.5)
                    )
                    .overlay {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(PirateTheme.flare)
                            .rotationEffect(.degrees(-15))
                    }
                    .scaleEffect(isRecording ? 1.15 : 1.0)
                    .neonGlow(PirateTheme.flare, intensity: isRecording ? 0.6 : 0.15)

                // Progress ring
                if isRecording {
                    Circle()
                        .trim(from: 0, to: recordingProgress)
                        .stroke(PirateTheme.broadcast, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)

                    // Mini waveform
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(PirateTheme.flare)
                                .frame(width: 3, height: waveformLevels[i] * 12)
                        }
                    }
                    .offset(y: 36)
                }
            }

            Text("Broadcast")
                .font(PirateTheme.body(9))
                .foregroundStyle(PirateTheme.flare.opacity(isRecording ? 1 : 0.6))
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.1)
                .onEnded { _ in startRecording() }
                .sequenced(before: DragGesture(minimumDistance: 0)
                    .onEnded { _ in stopRecording() }
                )
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
    }

    private func startRecording() {
        isRecording = true
        recordingProgress = 0

        Task {
            while !Task.isCancelled && isRecording {
                withAnimation(.easeInOut(duration: 0.15)) {
                    waveformLevels = (0..<5).map { _ in CGFloat.random(in: 0.15...1.0) }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        Task {
            let steps = 100
            for i in 0...steps {
                guard !Task.isCancelled && isRecording else { break }
                withAnimation(.linear(duration: maxRecordingSeconds / Double(steps))) {
                    recordingProgress = Double(i) / Double(steps)
                }
                try? await Task.sleep(for: .seconds(maxRecordingSeconds / Double(steps)))
            }
            if isRecording { stopRecording() }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingProgress = 0
        waveformLevels = Array(repeating: 0.2, count: 5)
        toastManager.show(.voiceClip, message: "Voice clip sent to crew!")
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
