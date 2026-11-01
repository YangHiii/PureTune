import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var audio: AudioPlayer

    let onOpen: () -> Void

    private var totalDuration: Double {
        max(audio.duration, 1)
    }

    private var displayedProgress: Double {
        min(max(audio.currentTime, 0), totalDuration)
    }

    var body: some View {
        if let song = audio.currentSong {
            VStack(spacing: 0) {
                ProgressView(value: displayedProgress, total: totalDuration)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(height: 2)

                HStack(spacing: 10) {
                    Button(action: onOpen) {
                        HStack(spacing: 11) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(song.displayArtist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开正在播放")

                    Spacer(minLength: 4)

                    playerButton(
                        systemName: "backward.end.fill",
                        label: "上一首",
                        action: { audio.previous() }
                    )

                    Button {
                        audio.togglePlayback()
                    } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

                    playerButton(
                        systemName: "forward.end.fill",
                        label: "下一首",
                        action: { audio.next() }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
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

    private func playerButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
