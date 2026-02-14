import SwiftUI

/// 3-page onboarding flow shown on first launch.
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var dialValue: Double = 0.3
    @State private var staticIntensity: Double = 0.3
    @State private var signalPulse = false

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            TabView(selection: $currentPage) {
                page1.tag(0)
                page2.tag(1)
                page3.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Skip button
            if currentPage < 2 {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            onComplete()
                        }
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Page 1: PIRATE RADIO

    private var page1: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                // CRT static behind dial
                CRTStaticOverlay(intensity: staticIntensity)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .opacity(0.4)

                FrequencyDial(value: $dialValue, color: PirateTheme.signal)
                    .frame(width: 180, height: 180)
            }
            .onAppear {
                // Animate dial spinning
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    dialValue = 1.0
                }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    staticIntensity = 0.6
                }
            }

            Text("PIRATE RADIO")
                .font(PirateTheme.display(36))
                .foregroundStyle(PirateTheme.signal)
                .neonGlow(PirateTheme.signal, intensity: 0.6)

            Text("Your crew. Your music.\nPerfectly synced.")
                .font(PirateTheme.body(16))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: HOW IT WORKS

    private var page2: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("HOW IT WORKS")
                .font(PirateTheme.display(28))
                .foregroundStyle(PirateTheme.broadcast)
                .neonGlow(PirateTheme.broadcast, intensity: 0.5)

            // DJ → signal → listeners diagram
            HStack(spacing: 20) {
                // DJ phone
                VStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 40))
                        .foregroundStyle(PirateTheme.broadcast)
                        .neonGlow(PirateTheme.broadcast, intensity: 0.5)
                    Text("DJ")
                        .font(PirateTheme.display(12))
                        .foregroundStyle(PirateTheme.broadcast)
                }

                // Signal waves
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 16))
                            .foregroundStyle(PirateTheme.signal.opacity(signalPulse ? 0.8 : 0.2))
                            .animation(
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                                value: signalPulse
                            )
                    }
                }

                // Listener phones
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                        Image(systemName: "iphone")
                    }
                    .font(.system(size: 32))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.3)
                    Text("Crew")
                        .font(PirateTheme.display(12))
                        .foregroundStyle(PirateTheme.signal)
                }
            }
            .padding(.vertical, 24)
            .onAppear { signalPulse = true }

            Text("One DJ controls the music.\nEveryone hears it at the same time.")
                .font(PirateTheme.body(15))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                featureChip(icon: "headphones", label: "Sync")
                featureChip(icon: "radio", label: "Tune In")
                featureChip(icon: "figure.skiing.downhill", label: "Ride")
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 3: SPOTIFY PREMIUM

    private var page3: some View {
        VStack(spacing: 32) {
            Spacer()

            // Spotify-green circle
            Circle()
                .fill(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.15))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                }

            Text("SPOTIFY PREMIUM")
                .font(PirateTheme.display(24))
                .foregroundStyle(.white)

            Text("Everyone needs Spotify Premium")
                .font(PirateTheme.body(16))
                .foregroundStyle(.white.opacity(0.7))

            Text("Each person streams from their own account — we keep you in sync")
                .font(PirateTheme.body(14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                onComplete()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Get Started")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func featureChip(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(label)
                .font(PirateTheme.body(11))
        }
        .foregroundStyle(PirateTheme.signal.opacity(0.7))
    }
}
