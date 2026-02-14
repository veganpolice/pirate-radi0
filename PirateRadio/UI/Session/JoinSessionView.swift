import SwiftUI

/// Enter a 4-digit code to join a session.
/// Two modes: classic code entry and a "tuning" hero interaction
/// where the user dials a FrequencyDial to find the session's station.
struct JoinSessionView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Shared state
    @State private var tuningMode = false

    // MARK: - Code entry state
    @State private var code = ""
    @FocusState private var isFocused: Bool

    // MARK: - Tuning state
    @State private var dialValue: Double = 0.5          // 0.0 – 1.0
    @State private var hasLocked = false
    @State private var lockTrigger = false               // drives sensoryFeedback

    // FM band constants
    private let fmMin: Double = 88.0
    private let fmMax: Double = 108.0
    private let lockThreshold: Double = 0.1              // within 0.1 MHz to lock

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 32) {
                header

                Spacer()

                // Mode title
                Text("TUNE IN")
                    .font(PirateTheme.display(32))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.6)

                // Mode picker
                modePicker

                if tuningMode {
                    tuningContent
                } else {
                    codeEntryContent
                }

                // Shared loading / error
                if sessionStore.isLoading {
                    ProgressView()
                        .tint(PirateTheme.signal)
                }

                if let error = sessionStore.error {
                    Text(error.errorDescription ?? "Failed to join")
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.flare)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 24)

            // CRT static overlay — visible only in tuning mode
            if tuningMode {
                CRTStaticOverlay(intensity: staticIntensity)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.3), value: staticIntensity)
            }
        }
        .onAppear {
            if !tuningMode { isFocused = true }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: lockTrigger)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(PirateTheme.body(14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("Mode", selection: $tuningMode) {
            Text("CODE").tag(false)
            Text("DIAL").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .onChange(of: tuningMode) { _, isTuning in
            if !isTuning {
                isFocused = true
            } else {
                isFocused = false
                hasLocked = false
            }
        }
    }

    // MARK: - Code entry mode (original behavior)

    private var codeEntryContent: some View {
        VStack(spacing: 24) {
            Text("enter the crew's frequency")
                .font(PirateTheme.body(14))
                .foregroundStyle(.white.opacity(0.5))

            // Code display
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    digitBox(at: index)
                }
            }

            // Hidden text field to capture keyboard input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    // Limit to 4 digits
                    if newValue.count > 4 {
                        code = String(newValue.prefix(4))
                    }
                    // Filter non-digits
                    code = newValue.filter(\.isNumber)

                    // Auto-join when 4 digits entered
                    if code.count == 4 {
                        Task {
                            await sessionStore.joinSession(code: code)
                            if sessionStore.error == nil {
                                dismiss()
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Tuning mode

    private var tuningContent: some View {
        VStack(spacing: 20) {
            // Frequency display
            Text(frequencyDisplayString)
                .font(PirateTheme.display(36))
                .foregroundStyle(hasLocked ? PirateTheme.signal : PirateTheme.signal.opacity(0.8))
                .neonGlow(PirateTheme.signal, intensity: hasLocked ? 1.0 : 0.3)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: currentFrequency)

            Text(hasLocked ? "LOCKED ON" : "dial to find the station")
                .font(PirateTheme.body(14))
                .foregroundStyle(hasLocked ? PirateTheme.signal : .white.opacity(0.5))
                .animation(.easeOut(duration: 0.3), value: hasLocked)

            // Dial
            FrequencyDial(
                value: $dialValue,
                color: hasLocked ? PirateTheme.signal : PirateTheme.broadcast,
                detents: fmDetents,
                onDetentSnap: { _ in }
            )
            .frame(width: 200, height: 200)
            .onChange(of: dialValue) { _, _ in
                evaluateTuning()
            }

            // Show the derived code when locked
            if hasLocked {
                Text("SESSION \(frequencyToCode(currentFrequency))")
                    .font(PirateTheme.body(13))
                    .foregroundStyle(PirateTheme.signal.opacity(0.6))
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    /// Current FM frequency based on dial position.
    private var currentFrequency: Double {
        let raw = fmMin + dialValue * (fmMax - fmMin)
        // Round to nearest 0.1
        return (raw * 10).rounded() / 10
    }

    /// Formatted frequency string like "107.3 FM".
    private var frequencyDisplayString: String {
        String(format: "%.1f FM", currentFrequency)
    }

    /// The target frequency derived from the session code the host shared.
    /// In real usage this would come from the code the user was told.
    /// For tuning mode we rely on the sessionStore's target code if available,
    /// but since the user doesn't know the code yet (they're dialing to find it),
    /// every valid code maps to a frequency and joining validates server-side.
    ///
    /// Convert a frequency back to a 4-digit code string.
    private func frequencyToCode(_ freq: Double) -> String {
        // 107.3 -> "1073", 88.1 -> "0881"
        let digits = Int((freq * 10).rounded())
        return String(format: "%04d", digits)
    }

    /// CRT static intensity: 1.0 when far from any valid signal, fades as user nears a station.
    /// Since we don't know the target ahead of time, we fade static at each 0.2 MHz
    /// boundary to simulate "stations" at standard FM increments — the real validation
    /// happens server-side on join.
    private var staticIntensity: Double {
        if hasLocked { return 0.0 }
        // FM stations are every 0.2 MHz in the US. Distance to nearest station slot.
        let stepsFromBase = (currentFrequency - fmMin) / 0.2
        let distToSlot = abs(stepsFromBase - stepsFromBase.rounded()) * 0.2
        // Map distance 0...0.1 to intensity 0...1
        let normalized = min(distToSlot / 0.1, 1.0)
        return normalized * 0.8 + 0.05 // always a tiny bit of noise
    }

    /// Build detent array: one detent per 1.0 MHz across the band.
    private var fmDetents: [Double] {
        stride(from: 0.0, through: 1.0, by: 1.0 / (fmMax - fmMin)).map { $0 }
    }

    /// Check whether dial is close enough to a valid station to auto-join.
    private func evaluateTuning() {
        guard !hasLocked, !sessionStore.isLoading else { return }

        // Round to nearest 0.1 — every 0.1 MHz is a potential code
        let freq = currentFrequency
        let stepsFromBase = (freq - fmMin) / 0.2
        let distToSlot = abs(stepsFromBase - stepsFromBase.rounded()) * 0.2

        if distToSlot < 0.05 {
            // Sitting on a station slot — attempt to join
            let joinCode = frequencyToCode(freq)
            hasLocked = true
            lockTrigger.toggle()

            Task {
                await sessionStore.joinSession(code: joinCode)
                if sessionStore.error == nil {
                    dismiss()
                } else {
                    // Wrong station — unlock and let user keep dialing
                    hasLocked = false
                }
            }
        }
    }

    // MARK: - Digit box (code entry mode)

    private func digitBox(at index: Int) -> some View {
        let digit = index < code.count
            ? String(code[code.index(code.startIndex, offsetBy: index)])
            : ""

        return Text(digit)
            .font(PirateTheme.display(40))
            .foregroundStyle(PirateTheme.signal)
            .frame(width: 60, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PirateTheme.signal.opacity(digit.isEmpty ? 0.05 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        digit.isEmpty ? PirateTheme.signal.opacity(0.3) : PirateTheme.signal,
                        lineWidth: 1.5
                    )
            )
            .neonGlow(PirateTheme.signal, intensity: digit.isEmpty ? 0 : 0.4)
            .onTapGesture { isFocused = true }
    }
}
