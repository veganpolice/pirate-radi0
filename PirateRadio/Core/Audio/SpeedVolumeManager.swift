import Foundation
import Observation
import AVFoundation

/// Speed zones for volume control.
enum SpeedZone: String {
    case stopped = "STOPPED"
    case chairlift = "CHAIRLIFT"
    case riding = "RIDING"
}

/// Adjusts system volume based on GPS speed. Volume only ever reduces from the user's set ceiling.
@Observable
@MainActor
final class SpeedVolumeManager {
    // MARK: - Public State

    private(set) var currentZone: SpeedZone = .stopped
    private(set) var smoothedSpeedMPH: Double = 0.0
    private(set) var isRunning = false

    // MARK: - Dependencies

    private let speedProvider: SpeedProvider
    private let volumeController: VolumeController
    private let settings: SpeedVolumeSettings

    // MARK: - Internal State

    private var userVolumeCeiling: Float = 1.0
    private var currentTargetMultiplier: Double = 1.0
    private var currentAppliedMultiplier: Double = 1.0
    private var speedTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var volumeObservation: NSKeyValueObservation?

    // EMA smoothing
    private let emaAlpha: Double = 0.3

    init(speedProvider: SpeedProvider, volumeController: VolumeController, settings: SpeedVolumeSettings) {
        self.speedProvider = speedProvider
        self.volumeController = volumeController
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Capture the user's current volume as the ceiling
        userVolumeCeiling = volumeController.currentVolume

        // Observe hardware volume changes to update ceiling
        startVolumeObservation()

        // Begin consuming speed stream
        speedTask = Task { [weak self] in
            guard let self else { return }
            let provider = self.speedProvider
            await provider.startUpdating()
            for await speed in provider.speedStream {
                guard !Task.isCancelled else { break }
                await self.handleSpeedUpdate(speed)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        speedTask?.cancel()
        speedTask = nil
        fadeTask?.cancel()
        fadeTask = nil
        volumeObservation?.invalidate()
        volumeObservation = nil

        Task { [speedProvider] in
            await speedProvider.stopUpdating()
        }

        // Restore volume to user ceiling
        volumeController.setVolume(userVolumeCeiling)
        currentAppliedMultiplier = 1.0
        currentTargetMultiplier = 1.0
        smoothedSpeedMPH = 0.0
        currentZone = .stopped
    }

    // MARK: - Speed Processing

    private func handleSpeedUpdate(_ rawSpeed: Double) {
        // EMA smoothing
        let clamped = max(0, rawSpeed)
        smoothedSpeedMPH = emaAlpha * clamped + (1 - emaAlpha) * smoothedSpeedMPH

        // Determine zone with hysteresis
        let newZone = computeZone(from: smoothedSpeedMPH)
        if newZone != currentZone {
            currentZone = newZone
            let multiplier = zoneMultiplier(for: newZone)
            fadeToMultiplier(multiplier)
        }
    }

    private func computeZone(from speed: Double) -> SpeedZone {
        let margin = settings.hysteresisMargin

        switch currentZone {
        case .stopped:
            if speed > settings.chairliftLow + margin {
                return .chairlift
            }
            if speed > settings.ridingThreshold + margin {
                return .riding
            }
            return .stopped

        case .chairlift:
            if speed < settings.stoppedThreshold - margin {
                return .stopped
            }
            if speed > settings.ridingThreshold + margin {
                return .riding
            }
            if speed < settings.chairliftLow - margin {
                return .stopped
            }
            return .chairlift

        case .riding:
            if speed < settings.ridingThreshold - margin {
                return .chairlift
            }
            if speed < settings.stoppedThreshold - margin {
                return .stopped
            }
            return .riding
        }
    }

    private func zoneMultiplier(for zone: SpeedZone) -> Double {
        switch zone {
        case .riding:
            return 1.0
        case .stopped:
            return settings.stoppedVolumePercent
        case .chairlift:
            switch settings.chairliftBehavior {
            case .quiet:
                return settings.stoppedVolumePercent
            case .vibing:
                return 1.0
            }
        }
    }

    // MARK: - Volume Fade

    private func fadeToMultiplier(_ target: Double) {
        fadeTask?.cancel()
        currentTargetMultiplier = target

        let startMultiplier = currentAppliedMultiplier
        let delta = target - startMultiplier
        let steps = 40
        let stepDuration: UInt64 = UInt64(settings.fadeDuration / Double(steps) * 1_000_000_000)

        fadeTask = Task { [weak self] in
            for i in 1...steps {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: stepDuration)
                guard !Task.isCancelled, let self else { return }

                let progress = Double(i) / Double(steps)
                let multiplier = startMultiplier + delta * progress
                self.currentAppliedMultiplier = multiplier

                let volume = Float(multiplier) * self.userVolumeCeiling
                self.volumeController.setVolume(min(volume, self.userVolumeCeiling))
            }
        }
    }

    // MARK: - Volume Ceiling Observation

    private func startVolumeObservation() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)

        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newVolume = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.userVolumeCeiling = newVolume
                // Re-apply current multiplier with new ceiling
                let volume = Float(self.currentAppliedMultiplier) * newVolume
                self.volumeController.setVolume(min(volume, newVolume))
            }
        }
    }
}
