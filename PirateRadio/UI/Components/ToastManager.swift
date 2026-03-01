import SwiftUI

/// In-app notification toast system with auto-dismiss and stacking.
@Observable
@MainActor
final class ToastManager {
    private(set) var toasts: [Toast] = []
    private let maxVisible = 3

    struct Toast: Identifiable {
        let id = UUID()
        let type: ToastType
        let message: String
        let color: Color
        let icon: String
        let timestamp = Date()
    }

    enum ToastType {
        case memberJoined, memberLeft, songRequest, djChanged
        case modeChanged, requestAccepted, requestDeclined
        case voteCast, signalLost, reconnected, voiceClip, comingSoon
    }

    func show(_ type: ToastType, message: String) {
        let toast = Toast(
            type: type,
            message: message,
            color: color(for: type),
            icon: icon(for: type)
        )

        withAnimation(.spring(duration: 0.4)) {
            toasts.append(toast)
            if toasts.count > maxVisible {
                toasts.removeFirst(toasts.count - maxVisible)
            }
        }

        // Auto-dismiss after 4s
        let toastID = toast.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.3)) {
                toasts.removeAll { $0.id == toastID }
            }
        }
    }

    func dismiss(_ toast: Toast) {
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll { $0.id == toast.id }
        }
    }

    private func icon(for type: ToastType) -> String {
        switch type {
        case .memberJoined: "person.badge.plus"
        case .memberLeft: "person.badge.minus"
        case .songRequest: "music.note.list"
        case .djChanged: "crown.fill"
        case .modeChanged: "slider.horizontal.3"
        case .requestAccepted: "checkmark.circle.fill"
        case .requestDeclined: "xmark.circle.fill"
        case .voteCast: "hand.thumbsup.fill"
        case .signalLost: "antenna.radiowaves.left.and.right.slash"
        case .reconnected: "antenna.radiowaves.left.and.right"
        case .voiceClip: "mic.fill"
        case .comingSoon: "wrench.and.screwdriver"
        }
    }

    private func color(for type: ToastType) -> Color {
        switch type {
        case .memberJoined, .reconnected, .requestAccepted: PirateTheme.signal
        case .djChanged, .modeChanged, .voteCast: PirateTheme.broadcast
        case .songRequest, .signalLost, .memberLeft, .requestDeclined: PirateTheme.flare
        case .voiceClip: PirateTheme.signal
        case .comingSoon: PirateTheme.flare
        }
    }
}

/// Compact toast ticker pinned to the top safe area.
/// Lives in its own dedicated strip so it never covers other UI.
struct ToastOverlay: View {
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        VStack {
            VStack(spacing: 4) {
                ForEach(toastManager.toasts) { toast in
                    toastView(toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.height < -10 {
                                        toastManager.dismiss(toast)
                                    }
                                }
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer()
        }
        .allowsHitTesting(!toastManager.toasts.isEmpty)
    }

    private func toastView(_ toast: ToastManager.Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(toast.color)

            Text(toast.message)
                .font(PirateTheme.body(11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            // Colored pip as dismiss hint
            Circle()
                .fill(toast.color.opacity(0.4))
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(PirateTheme.void.opacity(0.9))
                .overlay(
                    Capsule()
                        .strokeBorder(toast.color.opacity(0.25), lineWidth: 0.5)
                )
        )
        .sensoryFeedback(.impact(weight: .light), trigger: toast.id)
    }
}
