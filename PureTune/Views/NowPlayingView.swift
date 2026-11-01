import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var scrubTime: Double?

    var body: some View {
        ZStack {
            AuroraBackground()

            RadialGradient(
                colors: [
                    currentPalette.first?.opacity(0.18) ?? .clear,
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if let song = audio.currentSong {
                    ScrollView {
                        VStack(spacing: 24) {
                            artwork(for: song)
                                .padding(.top, 8)

                            songInformation(song)
                            timeline
                            controls

                            if let error = audio.playbackError {
                                errorBanner(error)
                            }

                            Spacer(minLength: 22)
                        }
                        .padding(.horizontal, 26)
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    emptyState
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: audio.currentSong?.id) { _ in
            scrubTime = nil
        }
    }

    private var currentPalette: [Color] {
        guard let song = audio.currentSong else { return [AppTheme.ice] }
        return ArtworkPalette.colors(for: song)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("正在播放")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(1.2)

                if !audio.queuePositionText.isEmpty {
                    Text(audio.queuePositionText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            Spacer()

            GlassIconButton(
                systemName: "xmark",
                label: "关闭",
                size: 42,
                action: { dismiss() }
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func artwork(for song: Song) -> some View {
        let palette = ArtworkPalette.colors(for: song)

        return RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        palette[0].opacity(0.88),
                        palette[1].opacity(0.64),
                        Color.black.opacity(0.32)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 300)
            .overlay {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 180, height: 180)

                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 230, height: 230)

                    Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.fileExtensionText)
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)

                    if !song.fileSizeText.isEmpty {
                        Text(song.fileSizeText)
                            .font(.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(18)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .shadow(color: palette[1].opacity(0.3), radius: 38, y: 22)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }

    private func songInformation(_ song: Song) -> some View {
        VStack(spacing: 7) {
            Text(song.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(song.displayArtist)
                .font(.headline.weight(.regular))
                .foregroundStyle(.white.opacity(0.57))
                .lineLimit(1)

            Text(song.displayAlbum)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.34))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
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
            .tint(AppTheme.ice)
            .disabled(audio.duration <= 0)

            HStack {
                Text(PlaybackTimeFormatter.string(from: scrubTime ?? audio.currentTime))
                Spacer()
                Text(PlaybackTimeFormatter.string(from: audio.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassPanel(cornerRadius: 20, strokeOpacity: 0.1)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            GlassIconButton(
                systemName: "backward.end.fill",
                label: "上一首",
                size: 54,
                action: { audio.previous() }
            )

            Button {
                audio.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white, AppTheme.ice.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 78, height: 78)

                    Circle()
                        .stroke(Color.white.opacity(0.74), lineWidth: 0.8)
                        .frame(width: 78, height: 78)

                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(.black.opacity(0.76))
                        .offset(x: audio.isPlaying ? 0 : 2)
                }
                .shadow(color: AppTheme.ice.opacity(0.22), radius: 24, y: 12)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

            GlassIconButton(
                systemName: "forward.end.fill",
                label: "下一首",
                size: 54,
                action: { audio.next() }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white.opacity(0.35))

            Text("当前没有正在播放的歌曲")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warm)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                audio.clearPlaybackError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭错误提示")
        }
        .padding(13)
        .glassPanel(cornerRadius: 17, tint: AppTheme.warm, strokeOpacity: 0.12)
    }
}
