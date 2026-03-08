import SwiftUI

/// Settings sheet accessible from gear icon on Now Playing.
/// DJ sees management controls; listeners see read-only info.
struct SessionSettingsView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss

    @State private var showEndConfirm = false
    @State private var showKickConfirm: Session.Member?
    @State private var showRecap = false
    @State private var chairliftMode = false

    private var isDJ: Bool { sessionStore.isDJ }

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                List {
                    // Chairlift mode toggle
                    chairliftSection

                    // Members section
                    membersSection

                    // Actions
                    actionsSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Remove Member", isPresented: .init(
                get: { showKickConfirm != nil },
                set: { if !$0 { showKickConfirm = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let member = showKickConfirm {
                        if PirateRadioApp.demoMode {
                            sessionStore.removeMember(member.id)
                            toastManager.show(.memberLeft, message: "\(member.displayName) removed")
                        } else {
                            toastManager.show(.comingSoon, message: "Remove member coming soon")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let member = showKickConfirm {
                    Text("Remove \(member.displayName) from the session?")
                }
            }
            .confirmationDialog("End Session", isPresented: $showEndConfirm) {
                Button("End Session", role: .destructive) {
                    Task { await sessionStore.leaveSession() }
                    showRecap = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("End the session for everyone?")
            }
            .fullScreenCover(isPresented: $showRecap) {
                SessionRecapView()
            }
        }
    }

    // MARK: - Sections

    private var chairliftSection: some View {
        Section {
            Toggle(isOn: $chairliftMode) {
                HStack(spacing: 8) {
                    Text("\u{1F6A1}")
                    Text("Chairlift Mode")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white)
                }
            }
            .tint(PirateTheme.signal)
        }
        .listRowBackground(Color.white.opacity(0.03))
    }

    private var membersSection: some View {
        Section {
            if let members = sessionStore.session?.members {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(member.avatarColor.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Text(String(member.displayName.prefix(1)).uppercased())
                                    .font(PirateTheme.display(14))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(PirateTheme.body(14))
                                .foregroundStyle(.white)
                            Text(member.id == sessionStore.session?.djUserID ? "DJ" : "Listener")
                                .font(PirateTheme.body(10))
                                .foregroundStyle(member.id == sessionStore.session?.djUserID ? PirateTheme.broadcast : PirateTheme.signal)
                        }

                        Spacer()

                        if isDJ && member.id != sessionStore.session?.creatorID {
                            Button {
                                showKickConfirm = member
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("CREW (\(sessionStore.session?.members.count ?? 0))")
                .font(PirateTheme.body(11))
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.03))
    }

    private var actionsSection: some View {
        Section {
            if isDJ {
                Button("End Session") {
                    showEndConfirm = true
                }
                .font(PirateTheme.body(16))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Button("Leave Session") {
                    Task { await sessionStore.leaveSession() }
                }
                .font(PirateTheme.body(16))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listRowBackground(Color.white.opacity(0.03))
    }
}
