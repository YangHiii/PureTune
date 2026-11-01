import SwiftUI

struct EffectsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var audio: AudioPlayer

    @State private var showingResetConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                equalizerCard
                enhancementCard
                sourceInformationCard
                resetCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "恢复默认音效配置？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认", role: .destructive) {
                settings.resetAudioEffects()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("EQ、音量均衡、淡入淡出、播放速度和音量都会恢复默认值。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AUDIO LAB")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(3.2)
                .foregroundStyle(AppTheme.mint)

            Text("音质与音效")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("所有开关都直接作用于当前播放引擎，不做装饰性选项")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var equalizerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("均衡器", systemImage: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Toggle("", isOn: $settings.equalizerEnabled)
                    .labelsHidden()
                    .tint(AppTheme.ice)
                    .accessibilityLabel("均衡器开关")
            }

            Text(settings.equalizerEnabled ? "10 段 EQ 已接入播放链路" : "EQ 已旁路，声音保持原始")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        PresetChip(
                            title: preset.title,
                            isSelected: settings.equalizerPreset == preset
                        ) {
                            settings.selectPreset(preset)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 11) {
                ForEach(Array(SettingsManager.frequencies.enumerated()), id: \.offset) { index, frequency in
                    EqualizerBandRow(
                        frequency: frequency,
                        gain: bandGain(at: index),
                        enabled: settings.equalizerEnabled,
                        binding: bandBinding(at: index)
                    )
                }
            }

            HStack {
                Text("增益范围限制为 ±12 dB，并为正增益预留前级余量。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.8))

                Spacer()

                Button {
                    settings.selectPreset(.flat)
                    settings.customEqualizerGains = Array(
                        repeating: 0,
                        count: SettingsManager.frequencies.count
                    )
                } label: {
                    Label("重置 EQ", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 27, tint: AppTheme.ice, strokeOpacity: 0.15)
    }

    private var enhancementCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("播放增强", systemImage: "waveform.path.ecg")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("音量均衡")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("播放时离线分析响度，只应用安全增益，不压缩动态")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.normalizationEnabled)
                        .labelsHidden()
                        .tint(AppTheme.mint)
                        .accessibilityLabel("音量均衡开关")
                }

                if settings.normalizationEnabled {
                    HStack {
                        Text("当前增益")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)

                        Spacer()

                        Text(String(format: "%+.1f dB", audio.currentNormalizationGainDB))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.mint)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Divider()
                .overlay(AppTheme.hairline)

            optionRow(
                title: "淡入淡出",
                subtitle: "切歌时平滑降低旧音量并提升新音量"
            ) {
                HStack(spacing: 7) {
                    ForEach(FadeOption.allCases) { option in
                        CompactOptionChip(
                            title: option.title,
                            isSelected: settings.fadeOption == option
                        ) {
                            settings.fadeOption = option
                        }
                    }
                }
            }

            optionRow(
                title: "播放速度",
                subtitle: "保持音高自然，不改变文件本身"
            ) {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(PlaybackRateOption.allCases) { option in
                            CompactOptionChip(
                                title: option.title,
                                isSelected: settings.playbackRate == option
                            ) {
                                settings.playbackRate = option
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Divider()
                .overlay(AppTheme.hairline)

            VStack(spacing: 9) {
                HStack {
                    Text("应用内音量")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Text("\(Int((settings.appVolume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textTertiary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)

                    Slider(value: $settings.appVolume, in: 0...1)
                        .tint(AppTheme.ice)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Text("仅调整 PureTune 的应用内增益，不越过系统或硬件音量限制。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 27, tint: AppTheme.mint, strokeOpacity: 0.15)
    }

    private var sourceInformationCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("音源信息", systemImage: "waveform.badge.magnifyingglass")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            if let song = audio.currentSong, let information = audio.currentSourceInfo {
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(song.displayArtist)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                VStack(spacing: 0) {
                    SourceInfoRow(label: "文件格式", value: information.fileFormat)
                    if let codec = information.codec {
                        SourceInfoRow(label: "编码", value: codec)
                    }
                    SourceInfoRow(label: "采样率", value: information.sampleRateText)
                    if let bitDepth = information.bitDepthText {
                        SourceInfoRow(label: "位深", value: bitDepth)
                    }
                    SourceInfoRow(label: "声道", value: information.channelText)
                    SourceInfoRow(label: "文件大小", value: information.fileSizeText)
                    SourceInfoRow(label: "播放时长", value: information.durationText)
                    if let lossless = information.losslessText {
                        SourceInfoRow(label: "编码类型", value: lossless)
                    }
                }

                Text("以上参数直接读取当前文件；不将系统输出格式冒充为原始音源参数。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
            } else {
                Text("播放一首歌曲后，这里会显示当前文件真实读取到的格式、采样率、位深、声道和文件大小。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 27, tint: AppTheme.lavender, strokeOpacity: 0.15)
    }

    private var resetCard: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 19, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("恢复默认音效配置")
                        .font(.subheadline.weight(.semibold))

                    Text("不会删除歌曲或改变主题")
                        .font(.caption2)
                        .opacity(0.7)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.45)
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(17)
            .glassPanel(cornerRadius: 22, tint: AppTheme.warm, strokeOpacity: 0.12)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func optionRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer()
            }

            content()
        }
    }

    private func bandGain(at index: Int) -> Float {
        let gains = settings.effectiveEqualizerGains
        return gains.indices.contains(index) ? gains[index] : 0
    }

    private func bandBinding(at index: Int) -> Binding<Double> {
        Binding(
            get: { Double(bandGain(at: index)) },
            set: { settings.setBandGain(index: index, value: Float($0)) }
        )
    }
}

private struct EqualizerBandRow: View {
    let frequency: Float
    let gain: Float
    let enabled: Bool
    @Binding var binding: Double

    private var frequencyText: String {
        if frequency >= 1_000 {
            return "\(Int(frequency / 1_000)) kHz"
        }
        return "\(Int(frequency)) Hz"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(frequencyText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 48, alignment: .leading)

            Slider(value: $binding, in: -12...12, step: 0.5)
                .tint(enabled ? AppTheme.ice : AppTheme.textTertiary)

            Text(String(format: "%+.1f dB", gain))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(enabled ? AppTheme.textSecondary : AppTheme.textTertiary)
                .frame(width: 62, alignment: .trailing)
        }
        .opacity(enabled ? 1 : 0.66)
    }
}

private struct PresetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    isSelected ? AppTheme.primaryButtonText : AppTheme.textSecondary
                )
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if isSelected {
                        Capsule().fill(AppTheme.accentGradient)
                    } else {
                        Capsule().fill(AppTheme.controlFill)
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(AppTheme.hairline.opacity(0.5), lineWidth: 0.7)
                }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct CompactOptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isSelected ? AppTheme.primaryButtonText : AppTheme.textSecondary
                )
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background {
                    if isSelected {
                        Capsule().fill(AppTheme.accentGradient)
                    } else {
                        Capsule().fill(AppTheme.controlFill)
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(AppTheme.hairline.opacity(0.45), lineWidth: 0.6)
                }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct SourceInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()

            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.hairline.opacity(0.3))
                .frame(height: 0.5)
        }
    }
}
