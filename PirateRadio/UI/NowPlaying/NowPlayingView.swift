import SwiftUI

/// The main now-playing screen shown during an active session.
/// Album art, track info, track tiles, crew strip, and bottom menu bar.
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
    @State private var showControls = false
    @State private var showCrew = false

    // Track progress — positionOrigin is the Date at which positionMs was 0
    @State private var positionOrigin: Date = .distantPast
    @State private var trackedTrackID: String?

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            // Pulsing beat background — behind all UI
            BeatPulseBackground(
                isPlaying: sessionStore.session?.isPlaying ?? false,
                members: sessionStore.session?.members ?? []
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
        .sheet(isPresented: $showSettings) { StationSettingsView() }
        .sheet(item: $showMemberProfile) { member in
            MemberProfileCard(member: member)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await sessionStore.leaveSession() }
                } label: {
                    Image(systemName: "dial.low")
                        .foregroundStyle(PirateTheme.signal)
                }
            }
        }
        .onAppear { startEntranceAnimation() }
        .onChange(of: sessionStore.session?.currentTrack?.id) { _, newTrackID in
            updatePositionOrigin(forTrackID: newTrackID)
        }
        .onChange(of: sessionStore.session?.isPlaying) { _, _ in
            updatePositionOrigin(forTrackID: sessionStore.session?.currentTrack?.id)
        }
        .onShake { handleShake() }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Station name header
            if let name = sessionStore.session?.stationName, !name.isEmpty {
                Text(name)
                    .font(PirateTheme.display(16))
                    .foregroundStyle(PirateTheme.signal)
                    .padding(.top, 8)
            }

            // Track tiles: current + upcoming + add bar
            if showArt {
                trackTiles
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Spacer()

            // Neon pirate fleet sailing between mountains
            NeonPirateScene(
                color: PirateTheme.signal,
                members: sessionStore.session?.members ?? []
            )
            .padding(.horizontal, 8)

            Spacer()

            // Crew strip
            if showCrew {
                crewStrip
                    .padding(.vertical, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Controls — universal skip + mute
            if showControls {
                stationControls
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
            // Messages / Requests
            Button { showRequests = true } label: {
                VStack(spacing: 3) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 20, weight: .medium))
                    Text("Messages")
                        .font(PirateTheme.body(9))
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

    // MARK: - Track Tiles

    private var trackTiles: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let progress = progressFraction(at: timeline.date)

            VStack(spacing: 8) {
                if let track = sessionStore.session?.currentTrack {
                    // Current track tile with progress bar
                    TrackTileView(
                        track: track,
                        style: .nowPlaying(progress: progress),
                        accentColor: PirateTheme.signal
                    )
                } else if sessionStore.session?.queue.isEmpty != false {
                    // Station is idle
                    VStack(spacing: 12) {
                        Image(systemName: "radio")
                            .font(.system(size: 36))
                            .foregroundStyle(PirateTheme.signal.opacity(0.3))
                        Text("Station is idle — add a song!")
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                }

                // Next 3 upcoming tracks
                let upcoming = Array((sessionStore.session?.queue ?? []).prefix(3))
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, track in
                    TrackTileView(
                        track: track,
                        style: .upcoming,
                        addedByEmoji: memberEmojis[index % memberEmojis.count]
                    )
                }

                // "+" add bar to open queue
                Button { showQueue = true } label: {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("Add to Queue")
                            .font(PirateTheme.body(13))
                    }
                    .foregroundStyle(PirateTheme.signal.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(PirateTheme.signal.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Progress Helpers

    /// Pure function — reads state without mutating it.
    private func progressFraction(at date: Date) -> Double {
        guard let track = sessionStore.session?.currentTrack,
              track.durationMs > 0,
              sessionStore.session?.isPlaying == true,
              positionOrigin != .distantPast else { return 0 }

        let elapsedSeconds = date.timeIntervalSince(positionOrigin)
        let durationSeconds = Double(track.durationMs) / 1000.0
        return min(1.0, max(0, elapsedSeconds / durationSeconds))
    }

    /// Called via onChange when track or playing state changes — safe to mutate @State here.
    private func updatePositionOrigin(forTrackID newTrackID: String?) {
        guard let track = sessionStore.session?.currentTrack,
              track.durationMs > 0,
              sessionStore.session?.isPlaying == true else {
            positionOrigin = .distantPast
            trackedTrackID = nil
            return
        }

        // Only reset origin when track actually changes
        if newTrackID != trackedTrackID {
            trackedTrackID = newTrackID
            // Backdate origin by the server's current playback position
            let currentPositionSec = sessionStore.currentPlaybackPosition
            positionOrigin = Date.now.addingTimeInterval(-currentPositionSec)
        }
    }

    private let memberEmojis = ["🏔️", "🎿", "🏂", "⛷️", "🦊", "🐻"]

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
                                            .strokeBorder(member.avatarColor.color, lineWidth: 2)
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

    // MARK: - Station Controls (universal)

    private var stationControls: some View {
        HStack(spacing: 20) {
            ConnectionStatusBadge(state: sessionStore.connectionState)

            Spacer()

            // Mute / Unmute (pauses local Spotify playback)
            Button {
                withAnimation(.spring(duration: 0.2)) { isMuted.toggle() }
                Task { await sessionStore.toggleMute() }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(PirateTheme.signal)
            }
            .frame(minWidth: 44, minHeight: 44)
            .sensoryFeedback(.impact(weight: .medium), trigger: isMuted)

            // Skip
            Button {
                if PirateRadioApp.demoMode {
                    sessionStore.demoSkipToNext()
                } else {
                    Task { await sessionStore.skipToNext() }
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(PirateTheme.signal)
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(sessionStore.session?.queue.isEmpty != false && sessionStore.session?.currentTrack == nil)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Entrance Animation

    private func startEntranceAnimation() {
        withAnimation(.spring(duration: 0.5)) { showArt = true }
        withAnimation(.spring(duration: 0.5).delay(0.3)) { showControls = true }
        withAnimation(.spring(duration: 0.5).delay(0.5)) { showCrew = true }
    }

    // MARK: - Debug Shake

    private func handleShake() {
        guard PirateRadioApp.demoMode else { return }
        let actions: [() -> Void] = [
            { showSignalLost = true },
            {
                toastManager.show(.memberJoined, message: "Gondola Greg joined the station")
                if let greg = MockData.members.first(where: { $0.displayName == "Gondola Greg" }) {
                    sessionStore.addMember(greg)
                }
            },
            {
                toastManager.show(.songRequest, message: "Shredder requested \"Midnight City\"")
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
