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

        observeInterruptions(session: session)
        observeRouteChanges(session: session)
    }

    /// Handle audio interruptions (phone calls, Siri, alarms).
    /// On interruption end: reactivate the session and restart the keep-alive.
    private func observeInterruptions(session: AVAudioSession) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                print("[PirateRadio] Audio session interrupted")
            case .ended:
                print("[PirateRadio] Audio interruption ended, reactivating session")
                try? AVAudioSession.sharedInstance().setActive(true)
                Task { @MainActor in
                    let keepAlive = BackgroundAudioKeepAlive.shared
                    if keepAlive.isRunning {
                        keepAlive.stop()
                        keepAlive.start()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    /// Handle audio route changes (headphones disconnected, Bluetooth lost, etc.).
    /// When the old route disappears, reactivate the session so the keep-alive
    /// continues on the new output (typically the built-in speaker).
    private func observeRouteChanges(session: AVAudioSession) {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            switch reason {
            case .oldDeviceUnavailable:
                // Headphones/Bluetooth disconnected — Spotify pauses automatically.
                // Reactivate our session so the keep-alive stays running.
                print("[PirateRadio] Audio route lost (headphones/BT disconnected)")
                try? AVAudioSession.sharedInstance().setActive(true)
                Task { @MainActor in
                    let keepAlive = BackgroundAudioKeepAlive.shared
                    if keepAlive.isRunning {
                        keepAlive.stop()
                        keepAlive.start()
                    }
                }
            case .newDeviceAvailable:
                print("[PirateRadio] New audio route available")
            default:
                break
            }
        }
    }
}
