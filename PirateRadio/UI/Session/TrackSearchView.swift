import SwiftUI

/// Search for Spotify tracks and select one to play.
struct TrackSearchView: View {
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var suggestions: [Track] = []
    @State private var isSearching = false
    @State private var isLoadingSuggestions = true
    @State private var searchTask: Task<Void, Never>?
    @State private var client: SpotifyClient?

    private var displayTracks: [Track] {
        query.isEmpty ? suggestions : results
    }

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
                            .onSubmit { performSearch() }

                        if !query.isEmpty {
                            Button {
                                query = ""
                                results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.08))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isSearching || (isLoadingSuggestions && query.isEmpty) {
                        Spacer()
                        ProgressView()
                            .tint(PirateTheme.signal)
                        Spacer()
                    } else if displayTracks.isEmpty && !query.isEmpty {
                        Spacer()
                        Text("No results")
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    } else {
                        if query.isEmpty && !suggestions.isEmpty {
                            Text("YOUR TOP TRACKS")
                                .font(PirateTheme.body(11))
                                .foregroundStyle(PirateTheme.signal.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                        }

                        List(displayTracks) { track in
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
            .task {
                client = SpotifyClient(authManager: authManager)
                await loadSuggestions()
            }
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                guard !newValue.isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    performSearch()
                }
            }
        }
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: track.albumArtURL)
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

            Text(formatDuration(track.durationMs))
                .font(PirateTheme.body(12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .contentShape(Rectangle())
    }

    private func loadSuggestions() async {
        guard let client else { return }
        do {
            suggestions = try await client.fetchTopTracks(limit: 20)
        } catch {
            suggestions = []
        }
        isLoadingSuggestions = false
    }

    private func performSearch() {
        let currentQuery = query.trimmingCharacters(in: .whitespaces)
        guard !currentQuery.isEmpty, let client else { return }
        isSearching = true
        Task {
            do {
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
