import Foundation

/// Test mock for VolumeController. Tracks all volume changes.
@MainActor
final class MockVolumeController: VolumeController {
    private(set) var volumeHistory: [Float] = []
    var currentVolume: Float = 1.0

    func setVolume(_ volume: Float) {
        currentVolume = volume
        volumeHistory.append(volume)
    }

    func reset() {
        currentVolume = 1.0
        volumeHistory = []
    }
}
