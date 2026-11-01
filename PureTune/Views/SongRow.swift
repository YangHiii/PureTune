import SwiftUI

struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool

    private var palette: [Color] {
        ArtworkPalette.colors(for: song)
    }

    var body: some View {
        HStack(spacing: 13) {
            artwork

            VStack(alignment: .leading, spacing: 5) {
                Text(song.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.92))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(song.displayArtist)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text("·")
                        Text(song.album)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            trailingStatus
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .glassPanel(
            cornerRadius: 20,
            tint: isCurrent ? palette[0] : .clear,
            strokeOpacity: isCurrent ? 0.26 : 0.1
        )
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                palette[0].opacity(0.42),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: palette.map { $0.opacity(isCurrent ? 0.82 : 0.52) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 52, height: 52)
            .overlay {
                Image(systemName: isCurrent && isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
            }
    }

    private var trailingStatus: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isCurrent {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlaying ? AppTheme.mint : Color.white.opacity(0.55))
                        .frame(width: 5, height: 5)

                    Text(isPlaying ? "播放中" : "已暂停")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.72))
            } else if song.duration > 0 {
                Text(song.durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.39))
            }

            HStack(spacing: 5) {
                Text(song.fileExtensionText)
                if !song.fileSizeText.isEmpty {
                    Text(song.fileSizeText)
                }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.27))
            .lineLimit(1)
        }
    }
}
