import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var scrubTime: Double?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.16, blue: 0.2),
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let song = audio.currentSong {
                ScrollView {
                    VStack(spacing: 28) {
                        artwork

                        VStack(spacing: 7) {
                            Text(song.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            Text(song.displayArtist)
                                .font(.headline.weight(.regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(song.displayAlbum)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)

                        timeline
                        controls

                        if let error = audio.playbackError {
                            errorBanner(error)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 54)
                    .padding(.bottom, 24)
                }
            } else {
                Text("当前没有正在播放的歌曲")
                    .foregroundStyle(.secondary)
            }

            closeButton
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.07),
                        Color.black.opacity(0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 300)
            .overlay {
                Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 30, y: 20)
    }

    private var timeline: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? audio.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(audio.duration, 0.01),
                onEditingChanged: { isEditing in
                    guard !isEditing, let value = scrubTime else { return }
                    audio.seek(to: value)
                    scrubTime = nil
                }
            )
            .tint(.white)
            .disabled(audio.duration <= 0)

            HStack {
                Text(PlaybackTimeFormatter.string(from: scrubTime ?? audio.currentTime))
                Spacer()
                Text(PlaybackTimeFormatter.string(from: audio.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 42) {
            controlButton(
                systemName: "backward.end.fill",
                size: 24,
                label: "上一首",
                action: { audio.previous() }
            )

            Button {
                audio.togglePlayback()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 74, height: 74)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

            controlButton(
                systemName: "forward.end.fill",
                size: 24,
                label: "下一首",
                action: { audio.next() }
            )
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()
        }
    }

    private func controlButton(
        systemName: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                audio.clearPlaybackError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭错误提示")
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
