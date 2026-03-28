import Foundation
import Observation

/// Per-device settings for speed-based volume control. Persisted via UserDefaults.
@Observable
@MainActor
final class SpeedVolumeSettings {
    // MARK: - User-Facing Settings

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Volume multiplier when stopped (0–1). Shown as 0–100% slider.
    var stoppedVolumePercent: Double {
        didSet { defaults.set(stoppedVolumePercent, forKey: Keys.stoppedVolumePercent) }
    }

    var chairliftBehavior: ChairliftBehavior {
        didSet { defaults.set(chairliftBehavior.rawValue, forKey: Keys.chairliftBehavior) }
    }

    // MARK: - Zone Thresholds (internal, not user-facing in v1)

    let stoppedThreshold: Double = 2.0       // mph
    let chairliftLow: Double = 4.0           // mph
    let ridingThreshold: Double = 10.0       // mph
    let hysteresisMargin: Double = 1.5       // mph
    let fadeDuration: Double = 2.0           // seconds

    // MARK: - Types

    enum ChairliftBehavior: String, CaseIterable {
        case quiet
        case vibing
    }

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.stoppedVolumePercent = defaults.object(forKey: Keys.stoppedVolumePercent) as? Double ?? 0.5
        let raw = defaults.string(forKey: Keys.chairliftBehavior) ?? ChairliftBehavior.quiet.rawValue
        self.chairliftBehavior = ChairliftBehavior(rawValue: raw) ?? .quiet
    }

    private enum Keys {
        static let isEnabled = "speedVolume.isEnabled"
        static let stoppedVolumePercent = "speedVolume.stoppedVolumePercent"
        static let chairliftBehavior = "speedVolume.chairliftBehavior"
    }
}
