import SwiftUI

/// A chunky tile displaying a track with album art, name, artist, and optional progress bar.
struct TrackTileView: View {
    let track: Track
    let style: TileStyle
    var addedByEmoji: String?
    var accentColor: Color = PirateTheme.signal

    enum TileStyle {
        case nowPlaying(progress: Double)
        case upcoming
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Album art
                albumArt

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(PirateTheme.display(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Right side: duration for now playing, emoji for upcoming
                switch style {
                case .nowPlaying:
                    Text(track.durationFormatted)
                        .font(PirateTheme.body(12))
                        .foregroundStyle(.white.opacity(0.3))
                case .upcoming:
                    if let emoji = addedByEmoji {
                        Text(emoji)
                            .font(.system(size: 20))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            // Progress bar (current track only)
            if case .nowPlaying(let progress) = style {
                progressBar(progress: progress)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay {
            if case .nowPlaying = style {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accentColor.opacity(0.4), lineWidth: 1)
            }
        }
        .neonGlow(glowColor, intensity: glowIntensity)
    }

    // MARK: - Album Art

    private var albumArt: some View {
        AsyncImage(url: track.albumArtURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.3))
                }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Progress Bar

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(accentColor)
                    .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 3)
    }

    // MARK: - Glow

    private var glowColor: Color {
        if case .nowPlaying = style { return accentColor }
        return .clear
    }

    private var glowIntensity: CGFloat {
        if case .nowPlaying = style { return 0.3 }
        return 0
    }
}
