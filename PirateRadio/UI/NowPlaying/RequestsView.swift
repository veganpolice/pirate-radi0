import SwiftUI

/// DJ inbox for incoming song requests — accept or decline.
struct RequestsView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss

    @State private var requests: [Track]

    init() {
        _requests = State(initialValue: MockData.pendingRequests)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PirateTheme.void.ignoresSafeArea()

                if requests.isEmpty {
                    emptyState
                } else {
                    requestList
                }
            }
            .navigationTitle("Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "radio")
                .font(.system(size: 48))
                .foregroundStyle(PirateTheme.signal.opacity(0.3))
            Text("No requests yet")
                .font(PirateTheme.body(16))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var requestList: some View {
        List {
            ForEach(requests) { track in
                requestRow(track)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func requestRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            // Album art
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

                if let requester = track.requestedBy {
                    Text("from \(requester)")
                        .font(PirateTheme.body(10))
                        .foregroundStyle(PirateTheme.signal.opacity(0.6))
                }
            }

            Spacer()

            // Accept
            Button {
                acceptRequest(track)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(PirateTheme.signal)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: track.id)

            // Decline
            Button {
                declineRequest(track)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(PirateTheme.flare.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(PirateTheme.snow)
    }

    private func acceptRequest(_ track: Track) {
        withAnimation {
            requests.removeAll { $0.id == track.id }
        }
        sessionStore.acceptRequest(track)
        toastManager.show(.requestAccepted, message: "Added \(track.name) to queue")
    }

    private func declineRequest(_ track: Track) {
        withAnimation {
            requests.removeAll { $0.id == track.id }
        }
        if let requester = track.requestedBy {
            toastManager.show(.requestDeclined, message: "Passed on \(requester)'s request")
        }
    }
}
