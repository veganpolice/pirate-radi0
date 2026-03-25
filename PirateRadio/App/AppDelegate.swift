import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    /// The active SpotifyPlayer, set by SessionStore when connecting to a session.
    /// AppDelegate needs a reference for lifecycle events (active/inactive).
    static var activePlayer: SpotifyPlayer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if !targetEnvironment(simulator)
        Self.activePlayer?.connect()
        #endif
    }

    func applicationWillResignActive(_ application: UIApplication) {
        #if !targetEnvironment(simulator)
        Self.activePlayer?.disconnect()
        #endif
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

    // MARK: - URL Handling (Spotify OAuth + App Remote)

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Try SPTAppRemote first (for App Remote authorization)
        #if !targetEnvironment(simulator)
        if let player = Self.activePlayer, player.handleURL(url) {
            return true
        }
        #endif

        // Fall through to OAuth redirect handling
        SpotifyAuthManager.handleRedirectURL(url)
        return true
    }
}
