import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var clock: PlaybackClock
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onOpenEffects: () -> Void

    @State private var scrubTime: Double?
    @State private var isScrubbing = false

    init(onOpenEffects: @escaping () -> Void = {}) {
        self.onOpenEffects = onOpenEffects
    }

    var body: some View {
        ZStack {
            playingBackground

            VStack(spacing: 0) {
                topBar

                if let song = audio.currentSong {
                    GeometryReader { proxy in
                        ScrollView {
                            if proxy.size.width > 650 {
                                landscapeLayout(song: song, size: proxy.size)
                            } else {
                                portraitLayout(song: song, size: proxy.size)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                } else {
                    emptyState
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: audio.currentSong?.id) { _ in
            scrubTime = nil
            isScrubbing = false
        }
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    @ViewBuilder
    private var playingBackground: some View {
        if let image = audio.currentArtwork {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 72)
                    .scaleEffect(1.14)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: isDark
                        ? [
                            Color.black.opacity(0.36),
                            Color.black.opacity(0.58),
                            Color.black.opacity(0.82)
                        ]
                        : [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.72),
                            Color(red: 0.93, green: 0.95, blue: 1).opacity(0.94)
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        } else {
            AuroraBackground()

            RadialGradient(
                colors: [
                    currentPalette.first?.opacity(isDark ? 0.22 : 0.32) ?? .clear,
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("NOW PLAYING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(AppTheme.textTertiary)

                if !audio.queuePositionText.isEmpty {
                    Text(audio.queuePositionText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.72))
                }
            }

            Spacer()

            GlassIconButton(
                systemName: "xmark",
                label: "关闭",
                size: 40,
                action: { dismiss() }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func portraitLayout(song: Song, size: CGSize) -> some View {
        VStack(spacing: 22) {
            artworkView(song: song, size: artworkSize(for: size))
                .padding(.top, 6)

            VStack(spacing: 18) {
                songInformation(song)
                timeline
                controls
                volumeControl
            }
            .frame(maxWidth: 430)

            Spacer(minLength: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func landscapeLayout(song: Song, size: CGSize) -> some View {
        HStack(alignment: .center, spacing: 28) {
            artworkView(song: song, size: artworkSize(for: size))

            VStack(spacing: 18) {
                songInformation(song)
                timeline
                controls
                volumeControl
            }
            .padding(.vertical, 8)
            .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    private func artworkSize(for size: CGSize) -> CGFloat {
        if size.width > 650 {
            return min(size.height * 0.58, 340, size.width * 0.4)
        }
        return min(size.width - 56, 330)
    }

    private func artworkView(song: Song, size: CGFloat) -> some View {
        let palette = ArtworkPalette.colors(for: song)

        return ZStack {
            LinearGradient(
                colors: [
                    palette[0].opacity(0.92),
                    palette[1].opacity(0.7),
                    Color.black.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = audio.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: size * 0.54, height: size * 0.54)

                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: size * 0.7, height: size * 0.7)

                    Image(systemName: audio.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: size * 0.22, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.36 : 0.8),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Text(song.fileExtensionText)
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)

                if let info = audio.currentSourceInfo {
                    Text(info.sampleRateText)
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(.white.opacity(0.74))
            .padding(16)
        }
        .shadow(color: palette[1].opacity(0.34), radius: 36, y: 20)
        .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 64 else {
                        return
                    }

                    if value.translation.width < 0 {
                        audio.next()
                    } else {
                        audio.previous()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.28), value: song.id)
        .accessibilityLabel("专辑封面，左右滑动可切歌")
    }

    private func songInformation(_ song: Song) -> some View {
        VStack(spacing: 7) {
            Text(song.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(song.displayArtist)
                .font(.headline.weight(.regular))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)

            Text(song.displayAlbum)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)

            metadataChips
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
    }

    private var metadataChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let info = audio.currentSourceInfo {
                    MetadataChip(text: info.fileFormat)
                    MetadataChip(text: info.sampleRateText)

                    if let bitDepth = info.bitDepthText {
                        MetadataChip(text: bitDepth)
                    }

                    MetadataChip(text: info.channelText)

                    if let lossless = info.losslessText {
                        MetadataChip(
                            text: lossless,
                            tint: info.isLossless == true ? AppTheme.mint : nil
                        )
                    }
                } else {
                    MetadataChip(text: "正在读取音源信息")
                }

                if settings.equalizerEnabled {
                    MetadataChip(text: "EQ 开", tint: AppTheme.ice)
                }

                if settings.normalizationEnabled {
                    MetadataChip(text: "响度均衡", tint: AppTheme.mint)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var timeline: some View {
        VStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? clock.time },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(audio.duration, 0.01),
                onEditingChanged: { editing in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isScrubbing = editing
                    }

                    guard !editing, let value = scrubTime else { return }
                    audio.seek(to: value)
                    scrubTime = nil
                }
            )
            .tint(AppTheme.ice)
            .scaleEffect(isScrubbing ? 1.03 : 1)
            .disabled(audio.duration <= 0)

            HStack {
                Text(PlaybackTimeFormatter.string(from: scrubTime ?? clock.time))
                Spacer()
                Text(PlaybackTimeFormatter.string(from: audio.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassPanel(cornerRadius: 20, strokeOpacity: 0.11)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            GlassIconButton(
                systemName: settings.playbackMode.systemImage,
                label: "播放模式：\(settings.playbackMode.title)",
                size: 40,
                action: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                        settings.cyclePlaybackMode()
                    }
                }
            )

            GlassIconButton(
                systemName: "backward.end.fill",
                label: "上一首",
                size: 44,
                action: { audio.previous() }
            )

            Button {
                audio.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 70, height: 70)

                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
                        .frame(width: 70, height: 70)

                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(AppTheme.primaryButtonText)
                        .offset(x: audio.isPlaying ? 0 : 2)
                }
                .shadow(color: AppTheme.ice.opacity(0.24), radius: 20, y: 10)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

            GlassIconButton(
                systemName: "forward.end.fill",
                label: "下一首",
                size: 44,
                action: { audio.next() }
            )

            GlassIconButton(
                systemName: "slider.horizontal.3",
                label: "打开音质与音效",
                size: 40,
                action: onOpenEffects
            )
        }
    }

    private var volumeControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("应用内音量")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()

                Text("\(Int((settings.appVolume * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textTertiary)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)

                Slider(value: $settings.appVolume, in: 0...1)
                    .tint(AppTheme.ice)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18, strokeOpacity: 0.1)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)

            Text("当前没有正在播放的歌曲")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentPalette: [Color] {
        guard let song = audio.currentSong else { return [AppTheme.ice] }
        return ArtworkPalette.colors(for: song)
    }
}

private struct MetadataChip: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(tint ?? AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                (tint ?? AppTheme.textTertiary).opacity(0.12),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke((tint ?? AppTheme.hairline).opacity(0.24), lineWidth: 0.6)
            }
    }
}
