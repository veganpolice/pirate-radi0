@preconcurrency import AVFoundation

/// Produces near-silent audio to keep the app process alive in the background.
///
/// iOS suspends apps that declare UIBackgroundModes "audio" but don't actually produce audio.
/// Since Spotify handles real music playback in a separate process, Pirate Radio needs its own
/// audio output to justify background execution. This keeps the sync engine's WebSocket
/// connection and drift correction loop running when the screen is off.
///
/// The generated tone is inaudible in practice (volume 0.001, ~20 Hz sine wave) but constitutes
/// real audio output, satisfying iOS background audio requirements.
@MainActor
final class BackgroundAudioKeepAlive {
    static let shared = BackgroundAudioKeepAlive()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isAttached = false

    private init() {}

    /// Start producing near-silent audio to prevent iOS from suspending the app.
    func start() {
        guard !engine.isRunning else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        if !isAttached {
            engine.attach(playerNode)
            isAttached = true
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.001

        do {
            try engine.start()
        } catch {
            print("[PirateRadio] Failed to start background audio engine: \(error)")
            return
        }

        // Generate a 1-second buffer of ~20 Hz sine wave and loop it forever.
        // 20 Hz is at the threshold of human hearing; combined with 0.001 volume,
        // this is imperceptible but keeps the audio session legitimately active.
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate) // 1 second
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[PirateRadio] Failed to allocate audio buffer")
            return
        }
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        let frequency: Float = 20.0
        let twoPiF = 2.0 * Float.pi * frequency
        for i in 0..<Int(frameCount) {
            samples[i] = sin(twoPiF * Float(i) / Float(sampleRate)) * 0.01
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    /// Stop background audio. Call when the user leaves all sessions.
    func stop() {
        playerNode.stop()
        engine.stop()
    }

    var isRunning: Bool { engine.isRunning }
}
