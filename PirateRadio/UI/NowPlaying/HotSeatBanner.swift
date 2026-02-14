import SwiftUI

/// Persistent banner showing current hot-seat DJ and songs remaining.
/// When countdown hits 0, shows full-screen "YOUR TURN" takeover.
struct HotSeatBanner: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var showTakeover = false
    @State private var takeoverOpacity: Double = 0

    var body: some View {
        if let session = sessionStore.session, session.djMode == .hotSeat {
            VStack(spacing: 0) {
                banner(session)

                if showTakeover {
                    takeoverView
                }
            }
        }
    }

    private func banner(_ session: Session) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))

            if let dj = session.members.first(where: { $0.id == session.djUserID }) {
                Text("DJ: \(dj.displayName)")
                    .font(PirateTheme.body(12))
            }

            Text("•")
                .foregroundStyle(.white.opacity(0.3))

            Text("\(session.hotSeatSongsRemaining) song\(session.hotSeatSongsRemaining == 1 ? "" : "s") left")
                .font(PirateTheme.body(12))

            Spacer()

            if session.hotSeatSongsRemaining <= 1 {
                Text("UP NEXT")
                    .font(PirateTheme.display(10))
                    .foregroundStyle(PirateTheme.flare)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(PirateTheme.flare.opacity(0.2)))
            }
        }
        .foregroundStyle(PirateTheme.broadcast)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PirateTheme.broadcast.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(PirateTheme.broadcast.opacity(0.3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var takeoverView: some View {
        ZStack {
            PirateTheme.void.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(PirateTheme.flare)
                    .neonGlow(PirateTheme.flare, intensity: 0.8)
                    .scaleEffect(showTakeover ? 1.0 : 0.3)

                Text("YOUR TURN TO DJ")
                    .font(PirateTheme.display(32))
                    .foregroundStyle(PirateTheme.broadcast)
                    .neonGlow(PirateTheme.broadcast, intensity: 0.8)
                    .scaleEffect(showTakeover ? 1.0 : 0.5)
            }
        }
        .opacity(takeoverOpacity)
        .onAppear {
            withAnimation(.spring(duration: 0.8)) {
                takeoverOpacity = 1.0
            }
            // Auto-dismiss after 2.5s
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.5)) {
                    takeoverOpacity = 0
                }
                try? await Task.sleep(for: .seconds(0.5))
                showTakeover = false
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: showTakeover)
    }

    /// Call this to trigger the rotation animation.
    func triggerRotation() {
        withAnimation(.spring(duration: 0.5)) {
            showTakeover = true
        }
    }
}
