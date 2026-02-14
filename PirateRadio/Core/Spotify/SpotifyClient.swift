import Foundation

/// Client for Spotify Web API (search, metadata, user profile).
/// All Spotify API calls happen client-side — tokens never leave the device.
actor SpotifyClient {
    private let authManager: SpotifyAuthManager

    init(authManager: SpotifyAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Search

    func searchTracks(query: String, limit: Int = 20) async throws -> [Track] {
        let token = try await authManager.getAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let searchResult = try JSONDecoder().decode(SearchResponse.self, from: data)
        return searchResult.tracks.items.map { item in
            Track(
                id: item.id,
                name: item.name,
                artist: item.artists.first?.name ?? "Unknown",
                albumName: item.album.name,
                albumArtURL: item.album.images.first.flatMap { URL(string: $0.url) },
                durationMs: item.durationMs
            )
        }
    }

    // MARK: - Track Metadata

    func getTrack(id: String) async throws -> Track {
        let token = try await authManager.getAccessToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/tracks/\(id)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let item = try JSONDecoder().decode(SpotifyTrack.self, from: data)
        return Track(
            id: item.id,
            name: item.name,
            artist: item.artists.first?.name ?? "Unknown",
            albumName: item.album.name,
            albumArtURL: item.album.images.first.flatMap { URL(string: $0.url) },
            durationMs: item.durationMs
        )
    }

    // MARK: - Audio Features

    func fetchAudioFeatures(trackID: String) async throws -> AudioFeatures {
        let token = try await authManager.getAccessToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/audio-features/\(trackID)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(AudioFeatures.self, from: data)
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200...299: return
        case 401: throw PirateRadioError.tokenExpired
        case 403: throw PirateRadioError.spotifyNotPremium
        default: throw PirateRadioError.playbackFailed(
            underlying: NSError(domain: "SpotifyAPI", code: httpResponse.statusCode)
        )
        }
    }
}

// MARK: - Spotify API Response Models

private struct SearchResponse: Codable {
    let tracks: TracksContainer

    struct TracksContainer: Codable {
        let items: [SpotifyTrack]
    }
}

private struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album
        case durationMs = "duration_ms"
    }
}

private struct SpotifyArtist: Codable {
    let id: String
    let name: String
}

private struct SpotifyAlbum: Codable {
    let name: String
    let images: [SpotifyImage]
}

private struct SpotifyImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

// MARK: - Audio Features Response

struct AudioFeatures: Codable, Sendable {
    let tempo: Double           // BPM, e.g. 120.0
    let timeSignature: Int      // Beats per bar, e.g. 4

    enum CodingKeys: String, CodingKey {
        case tempo
        case timeSignature = "time_signature"
    }
}
