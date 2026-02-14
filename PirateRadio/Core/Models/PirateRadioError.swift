import Foundation

enum PirateRadioError: LocalizedError {
    // Auth
    case spotifyNotInstalled
    case spotifyNotLoggedIn
    case spotifyNotPremium
    case tokenExpired
    case tokenRefreshFailed(underlying: Error)

    // Session
    case sessionNotFound
    case sessionFull
    case invalidJoinCode
    case notAuthorized(action: String)

    // Sync
    case clockSyncFailed
    case driftUnrecoverable(offsetMs: Int)
    case transportDisconnected

    // Playback
    case trackNotAvailable(trackID: String)
    case playbackFailed(underlying: Error)
    case playbackTimeout

    var errorDescription: String? {
        switch self {
        case .spotifyNotInstalled:
            return "Spotify is not installed. Please install Spotify to use Pirate Radio."
        case .spotifyNotLoggedIn:
            return "Please log in to Spotify first."
        case .spotifyNotPremium:
            return "Pirate Radio requires Spotify Premium. All crew members need their own Premium account."
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .tokenRefreshFailed:
            return "Failed to refresh your session. Please sign in again."
        case .sessionNotFound:
            return "Session not found. Check the code and try again."
        case .sessionFull:
            return "This session is full (max 10 crew members)."
        case .invalidJoinCode:
            return "Invalid session code."
        case .notAuthorized(let action):
            return "You're not authorized to \(action)."
        case .clockSyncFailed:
            return "Unable to sync clocks. Check your connection."
        case .driftUnrecoverable:
            return "Lost sync with the crew. Reconnecting..."
        case .transportDisconnected:
            return "Connection lost. Reconnecting..."
        case .trackNotAvailable(let id):
            return "Track \(id) is not available in your region."
        case .playbackFailed:
            return "Playback failed. Trying again..."
        case .playbackTimeout:
            return "Spotify is taking too long to respond."
        }
    }
}
