import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var audio: AudioPlayer

    let onOpen: () -> Void

    var body: some View {
        if let song = audio.currentSong {
            VStack(spacing: 0) {
                progressBar

                HStack(spacing: 11) {
                    Button(action: onOpen) {
                        HStack(spacing: 11) {
                            artwork(for: song)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)

                                Text(song.displayArtist)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开完整播放器")

                    controlButton(
                        systemName: audio.isPlaying ? "pause.fill" : "play.fill",
                        label: audio.isPlaying ? "暂停" : "播放",
                        emphasized: true,
                        action: { audio.togglePlayback() }
                    )

                    controlButton(
                        systemName: "forward.end.fill",
                        label: "下一首",
                        emphasized: false,
                        action: { audio.next() }
                    )
                }
                .padding(.horizontal, 13)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .glassPanel(cornerRadius: 24, tint: AppTheme.ice, strokeOpacity: 0.15)
        }
    }

    private var progressBar: some View {
        MiniPlaybackProgress()
        .frame(height: 2)
        .padding(.horizontal, 24)
        .padding(.top, 2)
    }

    private func artwork(for song: Song) -> some View {
        let colors = ArtworkPalette.colors(for: song)

        return ZStack {
            LinearGradient(
                colors: colors.map { $0.opacity(0.76) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = audio.artwork(for: song) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.hairline.opacity(0.8), lineWidth: 0.6)
        }
    }

    private func controlButton(
        systemName: String,
        label: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 14 : 13, weight: .bold))
                .foregroundStyle(emphasized ? AppTheme.primaryButtonText : AppTheme.textSecondary)
                .frame(width: emphasized ? 36 : 32, height: emphasized ? 36 : 36)
                .background {
                    if emphasized {
                        Circle()
                            .fill(AppTheme.accentGradient)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct MiniPlaybackProgress: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var clock: PlaybackClock

    private var progress: Double {
        guard audio.duration > 0 else { return 0 }
        return min(max(clock.time / audio.duration, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.textTertiary.opacity(0.16))

                Capsule()
                    .fill(AppTheme.accentGradient)
                    .frame(width: proxy.size.width * progress)
            }
        }
    }
}
