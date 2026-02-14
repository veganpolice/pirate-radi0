import SwiftUI

/// Queue management view: search for tracks and add to session queue.
/// DJ can reorder/remove; listeners can add requests.
/// In collab mode: vote buttons and auto-sort by vote count.
struct QueueView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [Track] = []
    @State private var isSearching = false
    @State private var spotifyClient: SpotifyClient?

    private var isCollabMode: Bool {
        sessionStore.session?.djMode == .collaborative
    }

    private var sortedQueue: [Track] {
        guard let queue = sessionStore.session?.queue else { return [] }
        if isCollabMode {
            return queue.sorted { $0.votes > $1.votes }
        }
        return queue
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Mode header for collab/hot-seat
                    if let mode = sessionStore.session?.djMode, mode != .solo {
                        modeHeader(mode)
                    }

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

                        if !sortedQueue.isEmpty {
                            Section {
                                ForEach(sortedQueue) { track in
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
                    .animation(.spring(duration: 0.4), value: sortedQueue.map(\.id))
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
                if PirateRadioApp.demoMode {
                    // Use mock search results in demo mode
                } else {
                    spotifyClient = SpotifyClient(authManager: authManager)
                }
            }
        }
    }

    private func modeHeader(_ mode: DJMode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: mode.icon)
                .font(.system(size: 14))
            Text(mode.rawValue.uppercased())
                .font(PirateTheme.display(12))

            if mode == .hotSeat, let dj = sessionStore.session?.members.first(where: { $0.id == sessionStore.session?.djUserID }) {
                Text("• DJ: \(dj.displayName)")
                    .font(PirateTheme.body(12))
            }
        }
        .foregroundStyle(PirateTheme.broadcast)
        .padding(.vertical, 8)
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

                // "Added by" label in collab mode
                if isCollabMode, let requester = track.requestedBy {
                    Text("Added by \(requester)")
                        .font(PirateTheme.body(10))
                        .foregroundStyle(PirateTheme.signal.opacity(0.5))
                }
            }

            Spacer()

            if isResult {
                // Add button for search results
                Button {
                    if PirateRadioApp.demoMode {
                        var t = track
                        t.requestedBy = "You"
                        sessionStore.acceptRequest(t)
                        withAnimation { searchResults.removeAll { $0.id == track.id } }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PirateTheme.signal)
                }
                .buttonStyle(.plain)
            } else if isCollabMode {
                // Vote buttons for collab queue
                voteControls(track)
            } else {
                Text(track.durationFormatted)
                    .font(PirateTheme.body(12))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(PirateTheme.snow)
    }

    private func voteControls(_ track: Track) -> some View {
        HStack(spacing: 8) {
            // Vote count badge
            Text("\(track.votes > 0 ? "+" : "")\(track.votes)")
                .font(PirateTheme.display(14))
                .foregroundStyle(track.votes > 0 ? PirateTheme.signal : track.votes < 0 ? PirateTheme.flare : .white.opacity(0.4))
                .frame(minWidth: 32)

            // Upvote
            Button {
                sessionStore.toggleVote(trackID: track.id, isUpvote: true)
            } label: {
                Image(systemName: track.isUpvotedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 16))
                    .foregroundStyle(track.isUpvotedByMe ? PirateTheme.signal : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: track.isUpvotedByMe)

            // Downvote
            Button {
                sessionStore.toggleVote(trackID: track.id, isUpvote: false)
            } label: {
                Image(systemName: track.isDownvotedByMe ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 16))
                    .foregroundStyle(track.isDownvotedByMe ? PirateTheme.flare : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: track.isDownvotedByMe)
        }
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true

        if PirateRadioApp.demoMode {
            // Filter mock tracks by search query
            let query = searchQuery.lowercased()
            searchResults = MockData.tracks.filter {
                $0.name.lowercased().contains(query) || $0.artist.lowercased().contains(query)
            }
            if searchResults.isEmpty {
                // Show some random tracks for demo
                searchResults = Array(MockData.tracks.shuffled().prefix(5))
            }
        } else {
            do {
                searchResults = try await spotifyClient?.searchTracks(query: searchQuery, limit: 10) ?? []
            } catch {
                searchResults = []
            }
        }

        isSearching = false
    }
}
