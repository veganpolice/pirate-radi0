import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }

    /// Configure audio session for background execution.
    /// Even though Spotify handles audio playback, Pirate Radio needs to stay alive
    /// in the background to maintain the sync engine's WebSocket connection.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PirateRadio] Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Spotify OAuth Redirect Handling

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        SpotifyAuthManager.handleRedirectURL(url)
        return true
    }
}
