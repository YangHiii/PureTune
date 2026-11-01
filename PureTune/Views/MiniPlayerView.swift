import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var audio: AudioPlayer

    let onOpen: () -> Void

    private var totalDuration: Double {
        max(audio.duration, 0.01)
    }

    private var progress: Double {
        min(max(audio.currentTime / totalDuration, 0), 1)
    }

    var body: some View {
        if let song = audio.currentSong {
            VStack(spacing: 0) {
                progressBar

                HStack(spacing: 10) {
                    Button(action: onOpen) {
                        HStack(spacing: 11) {
                            artwork(for: song)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.94))
                                    .lineLimit(1)

                                HStack(spacing: 5) {
                                    Text(song.displayArtist)
                                        .lineLimit(1)

                                    if !audio.queuePositionText.isEmpty {
                                        Text("·")
                                        Text(audio.queuePositionText)
                                            .monospacedDigit()
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.43))
                                .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开正在播放")

                    Spacer(minLength: 2)

                    controlButton(
                        systemName: "backward.end.fill",
                        label: "上一首",
                        action: { audio.previous() }
                    )

                    Button {
                        audio.togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.94))
                                .frame(width: 42, height: 42)

                            Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black.opacity(0.78))
                                .offset(x: audio.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

                    controlButton(
                        systemName: "forward.end.fill",
                        label: "下一首",
                        action: { audio.next() }
                    )
                }
                .padding(.horizontal, 13)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.025),
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.36), radius: 24, y: 12)
            .alert(
                "无法播放",
                isPresented: Binding(
                    get: { audio.playbackError != nil },
                    set: { isPresented in
                        if !isPresented {
                            audio.clearPlaybackError()
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {
                    audio.clearPlaybackError()
                }
            } message: {
                Text(audio.playbackError ?? "")
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.ice, AppTheme.lavender],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 24)
        .padding(.top, 2)
    }

    private func artwork(for song: Song) -> some View {
        let colors = ArtworkPalette.colors(for: song)

        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colors.map { $0.opacity(0.78) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
            }
    }

    private func controlButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 32, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }
}
