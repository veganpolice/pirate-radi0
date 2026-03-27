import SwiftUI

/// Bottom sheet showing member details and stats.
/// DJ sees additional actions like "Pass DJ".
struct MemberProfileCard: View {
    let member: Session.Member
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPassDJConfirm = false

    private var isDJ: Bool { sessionStore.isDJ }
    private var isMemberDJ: Bool { member.id == sessionStore.session?.djUserID }

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Avatar
            Circle()
                .fill(member.avatarColor.color.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isMemberDJ ? PirateTheme.broadcast : member.avatarColor.color,
                            lineWidth: 3
                        )
                )
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(PirateTheme.display(32))
                        .foregroundStyle(member.avatarColor.color)
                }

            // Name
            Text(member.displayName)
                .font(PirateTheme.display(22))
                .foregroundStyle(.white)

            // Role badge
            Text(isMemberDJ ? "DJ" : "Listener")
                .font(PirateTheme.display(12))
                .foregroundStyle(isMemberDJ ? PirateTheme.broadcast : PirateTheme.signal)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        (isMemberDJ ? PirateTheme.broadcast : PirateTheme.signal).opacity(0.15)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        (isMemberDJ ? PirateTheme.broadcast : PirateTheme.signal).opacity(0.3),
                        lineWidth: 0.5
                    )
                )

            // Stats grid
            HStack(spacing: 0) {
                statItem(value: "\(member.tracksAdded)", label: "Tracks")
                statDivider
                statItem(value: "\(member.votesCast)", label: "Votes")
                statDivider
                statItem(value: formatMinutes(member.djTimeMinutes), label: "DJ Time")
            }
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )

            // DJ Actions
            if isDJ && !isMemberDJ {
                Button {
                    showPassDJConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                        Text("Pass DJ to \(member.displayName)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(PirateTheme.void)
        .confirmationDialog("Pass DJ", isPresented: $showPassDJConfirm) {
            Button("Pass DJ") {
                if PirateRadioApp.demoMode {
                    sessionStore.setDJ(member.id)
                    toastManager.show(.djChanged, message: "\(member.displayName) is now DJ")
                } else {
                    toastManager.show(.comingSoon, message: "Pass DJ coming soon")
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make \(member.displayName) the DJ?")
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(PirateTheme.display(18))
                .foregroundStyle(PirateTheme.signal)
            Text(label)
                .font(PirateTheme.body(11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 0.5, height: 36)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
