import AVFoundation

/// Records short AAC voice clips for walkie-talkie transmission.
/// Manages AVAudioRecorder and audio session switching for recording.
actor VoiceClipRecorder {
    private var recorder: AVAudioRecorder?
    private var maxDurationTimer: Task<Void, Never>?
    private var recordingStartTime: Date?

    private let maxDuration: TimeInterval = 10

    struct Recording {
        let data: Data
        let durationMs: Int
    }

    enum RecordingError: Error {
        case microphonePermissionDenied
        case recordingFailed
    }

    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 22050,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    // MARK: - Recording

    func startRecording() async throws {
        // Request mic permission on first use
        let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
        guard granted else {
            throw RecordingError.microphonePermissionDenied
        }

        // Switch audio session to recording mode (ducks Spotify)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .default,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setActive(true)

        // Record to temp file
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let rec = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
        rec.record()
        self.recorder = rec
        self.recordingStartTime = Date()

        // Auto-stop after max duration
        maxDurationTimer = Task {
            try? await Task.sleep(for: .seconds(maxDuration))
            guard !Task.isCancelled else { return }
            // The caller is responsible for calling stopRecording;
            // this timer just stops the hardware recorder to cap duration.
            await stopRecorderHardware()
        }
    }

    func stopRecording() async throws -> Recording {
        maxDurationTimer?.cancel()
        maxDurationTimer = nil

        guard let rec = recorder else {
            throw RecordingError.recordingFailed
        }

        let duration = rec.currentTime
        rec.stop()
        let url = rec.url
        recorder = nil
        recordingStartTime = nil

        // Restore audio session to normal (unduck Spotify)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        // Read the recorded file
        guard let data = try? Data(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url)
            throw RecordingError.recordingFailed
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)

        let durationMs = Int(duration * 1000)
        return Recording(data: data, durationMs: max(durationMs, 1))
    }

    /// Cancel recording without producing output.
    func cancelRecording() async {
        maxDurationTimer?.cancel()
        maxDurationTimer = nil

        if let rec = recorder {
            rec.stop()
            try? FileManager.default.removeItem(at: rec.url)
            recorder = nil
        }
        recordingStartTime = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    private func stopRecorderHardware() {
        recorder?.stop()
    }
}

// AVAudioSession.requestRecordPermission returns in a callback;
// bridge to async.
private extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            self.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
