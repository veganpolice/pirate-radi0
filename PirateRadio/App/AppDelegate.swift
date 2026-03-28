import UIKit
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Reference to auth manager, set from PirateRadioApp.
    var authManager: SpotifyAuthManager?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }

    /// Handle deep link callbacks (pirate-radio://auth/callback).
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        authManager?.handleAppRemoteURL(url)
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

        // Restart the background keep-alive after interruptions (phone calls, Siri, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                Task { @MainActor in
                    if BackgroundAudioKeepAlive.shared.isRunning {
                        BackgroundAudioKeepAlive.shared.stop()
                        BackgroundAudioKeepAlive.shared.start()
                    }
                }
            }
        }
    }
}
