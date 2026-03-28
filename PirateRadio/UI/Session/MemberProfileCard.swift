import SwiftUI

/// Bottom sheet showing member details and stats.
struct MemberProfileCard: View {
    let member: Session.Member
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Avatar
            Circle()
                .fill(member.avatarColor.color.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(member.avatarColor.color, lineWidth: 3)
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

            // Stats grid
            HStack(spacing: 0) {
                statItem(value: "\(member.tracksAdded)", label: "Tracks")
                statDivider
                statItem(value: "\(member.votesCast)", label: "Votes")
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

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(PirateTheme.void)
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
}
