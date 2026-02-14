import SwiftUI

/// Enter a 4-digit code to join a session.
/// Large digit input with glove-friendly number pad.
struct JoinSessionView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.top, 16)

                Spacer()

                Text("TUNE IN")
                    .font(PirateTheme.display(32))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.6)

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
        }
        .onAppear { isFocused = true }
    }

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
