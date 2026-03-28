import Foundation
import MediaPlayer
import AVFoundation

/// Controls system volume via the hidden MPVolumeView slider.
@MainActor
final class SystemVolumeController: VolumeController {
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?

    var currentVolume: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    init() {
        setupVolumeView()
    }

    func setVolume(_ volume: Float) {
        let clamped = max(0, min(1, volume))
        volumeSlider?.value = clamped
    }

    private func setupVolumeView() {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true

        // Extract the hidden UISlider from MPVolumeView
        for subview in view.subviews {
            if let slider = subview as? UISlider {
                self.volumeSlider = slider
                break
            }
        }
        self.volumeView = view

        #if DEBUG
        if volumeSlider == nil {
            print("[SystemVolume] Warning: UISlider not found in MPVolumeView — volume control will be inoperable")
        }
        #endif
    }
}
