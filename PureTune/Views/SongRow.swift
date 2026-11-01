import SwiftUI

struct SongRow: View {
    let song: Song
    let fileURL: URL
    let isCurrent: Bool
    let isPlaying: Bool
    var onDelete: (() -> Void)?

    private var palette: [Color] {
        ArtworkPalette.colors(for: song)
    }

    var body: some View {
        HStack(spacing: 13) {
            ArtworkView(
                song: song,
                url: fileURL,
                cornerRadius: 13,
                isCurrent: isCurrent,
                isPlaying: isPlaying
            )
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(song.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary.opacity(isCurrent ? 1 : 0.92))
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
                .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer(minLength: 8)

            trailingStatus

            if let onDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("从曲库删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
            }
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
                                palette[0].opacity(0.48),
                                AppTheme.hairline.opacity(0.2)
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

    private var trailingStatus: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isCurrent {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlaying ? AppTheme.mint : AppTheme.textTertiary)
                        .frame(width: 5, height: 5)

                    Text(isPlaying ? "播放中" : "已暂停")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(AppTheme.textSecondary)
            } else if song.duration > 0 {
                Text(song.durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
            }

            HStack(spacing: 5) {
                Text(song.fileExtensionText)
                if !song.fileSizeText.isEmpty {
                    Text(song.fileSizeText)
                }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.textTertiary.opacity(0.66))
            .lineLimit(1)
        }
    }
}
