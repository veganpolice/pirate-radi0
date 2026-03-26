import SwiftUI

/// Search for Spotify tracks and select one to play.
struct TrackSearchView: View {
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.4))
                        TextField("Search tracks…", text: $query)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { search() }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(PirateTheme.signal)
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        Text("No results")
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    } else {
                        List(results) { track in
                            Button {
                                Task {
                                    await sessionStore.play(track: track)
                                    dismiss()
                                }
                            } label: {
                                trackRow(track)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.1))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Pick a Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .onChange(of: query) { _, newValue in
                // Debounced search
                searchTask?.cancel()
                guard !newValue.isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    search()
                }
            }
        }
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            // Album art
            AsyncImage(url: track.albumArtURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.1))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(PirateTheme.body(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(PirateTheme.body(12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            // Duration
            Text(formatDuration(track.durationMs))
                .font(PirateTheme.body(12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .contentShape(Rectangle())
    }

    private func search() {
        let currentQuery = query
        guard !currentQuery.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let client = SpotifyClient(authManager: authManager)
                results = try await client.searchTracks(query: currentQuery)
            } catch {
                results = []
            }
            isSearching = false
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
