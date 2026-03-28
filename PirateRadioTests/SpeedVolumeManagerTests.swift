import Testing
import Foundation
@testable import PirateRadio

@Suite("SpeedVolumeManager")
@MainActor
struct SpeedVolumeManagerTests {

    // MARK: - Helpers

    private func makeSUT(
        stoppedVolumePercent: Double = 0.5,
        chairliftBehavior: SpeedVolumeSettings.ChairliftBehavior = .quiet
    ) -> (SpeedVolumeManager, MockSpeedProvider, MockVolumeController, SpeedVolumeSettings) {
        let settings = SpeedVolumeSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.isEnabled = true
        settings.stoppedVolumePercent = stoppedVolumePercent
        settings.chairliftBehavior = chairliftBehavior

        let provider = MockSpeedProvider()
        let volume = MockVolumeController()
        volume.currentVolume = 1.0

        let manager = SpeedVolumeManager(
            speedProvider: provider,
            volumeController: volume,
            settings: settings
        )
        return (manager, provider, volume, settings)
    }

    /// Wait briefly for async processing.
    private func settle(ms: UInt64 = 100) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    // MARK: - Zone Transitions

    @Test("Starts in stopped zone")
    func startsInStoppedZone() async {
        let (manager, _, _, _) = makeSUT()
        #expect(manager.currentZone == .stopped)
    }

    @Test("High speed transitions to riding zone")
    func highSpeedTransitionsToRiding() async {
        let (manager, provider, _, _) = makeSUT()
        manager.start()
        await settle()

        // Send several high-speed readings to overcome EMA smoothing
        for _ in 0..<10 {
            await provider.send(speed: 25.0)
            await settle(ms: 20)
        }
        await settle(ms: 200)

        #expect(manager.currentZone == .riding)
        manager.stop()
    }

    @Test("Chairlift speed enters chairlift zone")
    func chairliftSpeedEntersChairliftZone() async {
        let (manager, provider, _, _) = makeSUT()
        manager.start()
        await settle()

        // Send chairlift-speed readings (7 mph, within 4-10 range)
        for _ in 0..<10 {
            await provider.send(speed: 7.0)
            await settle(ms: 20)
        }
        await settle(ms: 200)

        #expect(manager.currentZone == .chairlift)
        manager.stop()
    }

    // MARK: - Hysteresis

    @Test("Hysteresis prevents oscillation at zone boundary")
    func hysteresisPreventsOscillation() async {
        let (manager, provider, _, _) = makeSUT()
        manager.start()
        await settle()

        // Push firmly into riding
        for _ in 0..<10 {
            await provider.send(speed: 20.0)
            await settle(ms: 20)
        }
        await settle(ms: 200)
        #expect(manager.currentZone == .riding)

        // Drop just below threshold but within hysteresis margin (10 - 1.5 = 8.5)
        // Speed of 9.0 should NOT trigger zone change
        for _ in 0..<5 {
            await provider.send(speed: 9.0)
            await settle(ms: 20)
        }
        await settle(ms: 200)

        // Should still be riding due to hysteresis
        #expect(manager.currentZone == .riding)
        manager.stop()
    }

    // MARK: - Volume Ceiling

    @Test("Volume never exceeds user ceiling")
    func volumeNeverExceedsCeiling() async {
        let (manager, provider, volume, _) = makeSUT()
        volume.currentVolume = 0.7  // User set volume to 70%
        manager.start()
        await settle()

        // Go to riding (full volume) — should be capped at 0.7
        for _ in 0..<10 {
            await provider.send(speed: 25.0)
            await settle(ms: 20)
        }
        // Wait for fade to complete
        await settle(ms: 2500)

        let maxVolume = volume.volumeHistory.max() ?? 0
        #expect(maxVolume <= 0.7 + 0.01)  // Small float tolerance
        manager.stop()
    }

    // MARK: - Stopped Zone Multiplier

    @Test("Stopped zone applies stoppedVolumePercent multiplier")
    func stoppedZoneAppliesMultiplier() async {
        let (manager, provider, volume, _) = makeSUT(stoppedVolumePercent: 0.3)
        volume.currentVolume = 1.0
        manager.start()
        await settle()

        // First go to riding
        for _ in 0..<10 {
            await provider.send(speed: 25.0)
            await settle(ms: 20)
        }
        await settle(ms: 2500)

        // Then stop
        for _ in 0..<10 {
            await provider.send(speed: 0.0)
            await settle(ms: 20)
        }
        // Wait for fade
        await settle(ms: 2500)

        // Volume should be near 0.3 (30% of 1.0 ceiling)
        let lastVolume = volume.currentVolume
        #expect(abs(lastVolume - 0.3) < 0.05)
        manager.stop()
    }

    // MARK: - Chairlift Behavior

    @Test("Chairlift quiet mode reduces volume")
    func chairliftQuietReducesVolume() async {
        let (manager, provider, volume, _) = makeSUT(
            stoppedVolumePercent: 0.4,
            chairliftBehavior: .quiet
        )
        manager.start()
        await settle()

        // Go to chairlift speed
        for _ in 0..<10 {
            await provider.send(speed: 7.0)
            await settle(ms: 20)
        }
        await settle(ms: 2500)

        // Quiet chairlift should use stoppedVolumePercent
        let lastVolume = volume.currentVolume
        #expect(lastVolume < 0.8)  // Should be reduced
        manager.stop()
    }

    @Test("Chairlift vibing mode keeps full volume")
    func chairliftVibingKeepsFullVolume() async {
        let (manager, provider, volume, _) = makeSUT(
            stoppedVolumePercent: 0.4,
            chairliftBehavior: .vibing
        )
        manager.start()
        await settle()

        // Go to chairlift speed
        for _ in 0..<10 {
            await provider.send(speed: 7.0)
            await settle(ms: 20)
        }
        await settle(ms: 2500)

        // Vibing should keep multiplier at 1.0
        let lastVolume = volume.currentVolume
        #expect(lastVolume > 0.8)
        manager.stop()
    }

    // MARK: - Disable Restores Volume

    @Test("Stopping restores volume to user ceiling")
    func stopRestoresVolume() async {
        let (manager, provider, volume, _) = makeSUT(stoppedVolumePercent: 0.3)
        volume.currentVolume = 0.8
        manager.start()
        await settle()

        // Drop to stopped
        for _ in 0..<5 {
            await provider.send(speed: 0.0)
            await settle(ms: 20)
        }
        await settle(ms: 2500)

        // Volume should be reduced
        #expect(volume.currentVolume < 0.7)

        // Now stop the manager
        manager.stop()

        // Should restore to ceiling
        #expect(abs(volume.currentVolume - 0.8) < 0.01)
    }
}
