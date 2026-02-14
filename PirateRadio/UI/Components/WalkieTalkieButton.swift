import SwiftUI

/// Floating push-to-talk button with recording visualization.
struct WalkieTalkieButton: View {
    @Environment(ToastManager.self) private var toastManager

    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var waveformLevels: [CGFloat] = Array(repeating: 0.2, count: 7)
    @State private var incomingClip: IncomingClip?

    struct IncomingClip: Identifiable {
        let id = UUID()
        let from: String
        let duration: String
    }

    private let maxRecordingSeconds: Double = 10

    var body: some View {
        VStack(spacing: 8) {
            // Incoming clip bubble
            if let clip = incomingClip {
                clipBubble(clip)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Recording indicator
            if isRecording {
                recordingIndicator
                    .transition(.scale.combined(with: .opacity))
            }

            // PTT Button
            Circle()
                .fill(isRecording ? PirateTheme.flare.opacity(0.2) : PirateTheme.void)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .strokeBorder(PirateTheme.flare, lineWidth: isRecording ? 3 : 1.5)
                )
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(PirateTheme.flare)
                }
                .scaleEffect(isRecording ? 1.2 : 1.0)
                .neonGlow(PirateTheme.flare, intensity: isRecording ? 0.6 : 0.2)
                .overlay {
                    // Progress ring
                    if isRecording {
                        Circle()
                            .trim(from: 0, to: recordingProgress)
                            .stroke(PirateTheme.broadcast, lineWidth: 3)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 66, height: 66)
                    }
                }
                .gesture(
                    LongPressGesture(minimumDuration: 0.1)
                        .onEnded { _ in startRecording() }
                        .sequenced(before: DragGesture(minimumDistance: 0)
                            .onEnded { _ in stopRecording() }
                        )
                )
                .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(PirateTheme.flare)
                    .frame(width: 4, height: waveformLevels[i] * 24)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(PirateTheme.void.opacity(0.9))
        )
        .overlay(Capsule().strokeBorder(PirateTheme.flare.opacity(0.3), lineWidth: 0.5))
    }

    private func clipBubble(_ clip: IncomingClip) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PirateTheme.signal.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(clip.from.prefix(1)).uppercased())
                        .font(PirateTheme.display(12))
                        .foregroundStyle(PirateTheme.signal)
                }

            // Mini waveform
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PirateTheme.signal.opacity(0.5))
                        .frame(width: 3, height: CGFloat.random(in: 4...14))
                }
            }

            Text(clip.duration)
                .font(PirateTheme.body(10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(PirateTheme.void.opacity(0.9))
        )
        .overlay(Capsule().strokeBorder(PirateTheme.signal.opacity(0.2), lineWidth: 0.5))
    }

    private func startRecording() {
        isRecording = true
        recordingProgress = 0

        // Animate waveform
        let waveTask = Task {
            while !Task.isCancelled && isRecording {
                withAnimation(.easeInOut(duration: 0.15)) {
                    waveformLevels = (0..<7).map { _ in CGFloat.random(in: 0.15...1.0) }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        // Animate progress
        let progressTask = Task {
            let steps = 100
            for i in 0...steps {
                guard !Task.isCancelled && isRecording else { break }
                withAnimation(.linear(duration: maxRecordingSeconds / Double(steps))) {
                    recordingProgress = Double(i) / Double(steps)
                }
                try? await Task.sleep(for: .seconds(maxRecordingSeconds / Double(steps)))
            }
            if isRecording { stopRecording() }
        }

        _ = (waveTask, progressTask)
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingProgress = 0
        waveformLevels = Array(repeating: 0.2, count: 7)

        toastManager.show(.voiceClip, message: "Voice clip sent to crew!")

        // Show fake incoming clip after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            let names = ["Shredder", "Avalanche", "Fresh Tracks"]
            withAnimation(.spring(duration: 0.4)) {
                incomingClip = IncomingClip(from: names.randomElement()!, duration: "3s")
            }
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut(duration: 0.3)) {
                incomingClip = nil
            }
        }
    }
}
