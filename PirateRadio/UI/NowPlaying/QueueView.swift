import SwiftUI

/// Queue management view: search for tracks and add to session queue.
/// DJ can reorder/remove; listeners can add requests.
struct QueueView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [Track] = []
    @State private var isSearching = false
    @State private var spotifyClient: SpotifyClient?

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(PirateTheme.signal.opacity(0.5))

                        TextField("Search tracks...", text: $searchQuery)
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await search() } }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.05))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isSearching {
                        ProgressView()
                            .tint(PirateTheme.signal)
                            .padding(.top, 24)
                    }

                    // Results / Queue
                    List {
                        if !searchResults.isEmpty {
                            Section {
                                ForEach(searchResults) { track in
                                    trackRow(track, isResult: true)
                                }
                            } header: {
                                Text("SEARCH RESULTS")
                                    .font(PirateTheme.body(11))
                                    .foregroundStyle(PirateTheme.signal.opacity(0.6))
                            }
                        }

                        if let queue = sessionStore.session?.queue, !queue.isEmpty {
                            Section {
                                ForEach(queue) { track in
                                    trackRow(track, isResult: false)
                                }
                            } header: {
                                Text("UP NEXT")
                                    .font(PirateTheme.body(11))
                                    .foregroundStyle(PirateTheme.broadcast.opacity(0.6))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                spotifyClient = SpotifyClient(authManager: authManager)
            }
        }
    }

    private func trackRow(_ track: Track, isResult: Bool) -> some View {
        HStack(spacing: 12) {
            // Album art thumbnail
            if let url = track.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PirateTheme.signal.opacity(0.1))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(PirateTheme.body(12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Text(track.durationFormatted)
                .font(PirateTheme.body(12))
                .foregroundStyle(.white.opacity(0.3))

            if isResult {
                Button {
                    // TODO: Add to queue via session store
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PirateTheme.signal)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(PirateTheme.snow)
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true

        do {
            searchResults = try await spotifyClient?.searchTracks(query: searchQuery, limit: 10) ?? []
        } catch {
            searchResults = []
        }

        isSearching = false
    }
}
