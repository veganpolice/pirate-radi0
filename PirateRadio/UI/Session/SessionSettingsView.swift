import SwiftUI

/// Settings sheet for the current station.
/// Shows members, chairlift mode toggle, and leave button.
struct StationSettingsView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SpeedVolumeSettings.self) private var speedVolumeSettings
    @Environment(\.dismiss) private var dismiss

    @State private var chairliftMode = false
    @State private var showRecap = false

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                List {
                    // Chairlift mode toggle
                    chairliftSection

                    // Speed-based volume control
                    speedVolumeSection

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

    private var speedVolumeSection: some View {
        @Bindable var settings = speedVolumeSettings
        return Section {
            Toggle(isOn: $settings.isEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .foregroundStyle(PirateTheme.signal)
                    Text("Speed Volume")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white)
                }
            }
            .tint(PirateTheme.signal)

            if settings.isEnabled {
                // Quiet volume slider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quiet Volume")
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.6))
                    Slider(value: $settings.stoppedVolumePercent, in: 0...1)
                        .tint(PirateTheme.signal)
                    Text("\(Int(settings.stoppedVolumePercent * 100))%")
                        .font(PirateTheme.display(12))
                        .foregroundStyle(PirateTheme.signal)
                }

                // Chairlift behavior picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chairlift Mode")
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.6))
                    Picker("Chairlift", selection: $settings.chairliftBehavior) {
                        Text("Quiet").tag(SpeedVolumeSettings.ChairliftBehavior.quiet)
                        Text("Vibing").tag(SpeedVolumeSettings.ChairliftBehavior.vibing)
                    }
                    .pickerStyle(.segmented)
                }
            }
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

                        Text(member.displayName)
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                }
            }
        } header: {
            Text("LISTENERS (\(sessionStore.session?.members.count ?? 0))")
                .font(PirateTheme.body(11))
                .foregroundStyle(PirateTheme.signal.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.03))
    }

    private var actionsSection: some View {
        Section {
            Button("Leave Station") {
                dismiss()
                Task { await sessionStore.leaveSession() }
            }
            .font(PirateTheme.body(16))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.white.opacity(0.03))
    }
}
