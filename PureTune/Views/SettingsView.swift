import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var library: MusicLibrary

    let onOpenEffects: () -> Void

    @State private var showingResetConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                themeCard
                audioEntryCard
                playbackCard
                libraryCard
                aboutCard
                resetCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "恢复 PureTune 默认设置？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认设置", role: .destructive) {
                settings.resetToDefaults()
                themeManager.reset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会重置主题、音效、播放模式和音量，不会删除歌曲或曲库索引。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PREFERENCES")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(3.2)
                .foregroundStyle(AppTheme.warm)

            Text("设置")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("主题、播放行为与本地曲库都保存在这台设备")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var themeCard: some View {
        SettingsCard(title: "外观", systemImage: "paintpalette.fill", tint: AppTheme.ice) {
            HStack(spacing: 9) {
                ForEach(ThemeMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.mode = mode
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 18, weight: .semibold))

                            Text(mode.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            themeManager.mode == mode
                                ? AppTheme.primaryButtonText
                                : AppTheme.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background {
                            if themeManager.mode == mode {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.accentGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.controlFill)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.hairline.opacity(0.5), lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }

            Text("跟随系统会实时适配 iOS 浅色与深色外观，选择会持久保存。")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var audioEntryCard: some View {
        Button(action: onOpenEffects) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.mint.opacity(0.28), AppTheme.ice.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("音质与音效")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(audioSummary)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
            }
            .padding(16)
            .glassPanel(cornerRadius: 24, tint: AppTheme.mint, strokeOpacity: 0.14)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var playbackCard: some View {
        SettingsCard(title: "播放行为", systemImage: "play.circle.fill", tint: AppTheme.lavender) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 138), spacing: 9)],
                spacing: 9
            ) {
                ForEach(PlaybackMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.playbackMode = mode
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 13, weight: .semibold))

                            Text(mode.title)
                                .font(.caption.weight(.semibold))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(
                            settings.playbackMode == mode
                                ? AppTheme.primaryButtonText
                                : AppTheme.textSecondary
                        )
                        .padding(.horizontal, 11)
                        .frame(height: 42)
                        .background {
                            if settings.playbackMode == mode {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(AppTheme.accentGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(AppTheme.controlFill)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(AppTheme.hairline.opacity(0.45), lineWidth: 0.6)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }

            Text("播放模式会同步到自动切歌与锁屏/耳机控制。")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var libraryCard: some View {
        SettingsCard(title: "音乐库管理", systemImage: "internaldrive.fill", tint: AppTheme.warm) {
            HStack(spacing: 10) {
                LibraryStatTile(
                    value: "\(library.songs.count)",
                    label: "首歌曲"
                )

                LibraryStatTile(
                    value: ByteCountFormatter.string(
                        fromByteCount: library.totalFileSize,
                        countStyle: .file
                    ),
                    label: "本地占用"
                )
            }

            Button {
                library.reconcileLibrary()
            } label: {
                HStack {
                    Label("检查并清理失效记录", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(AppTheme.hairline.opacity(0.45), lineWidth: 0.6)
                }
            }
            .buttonStyle(ScaleButtonStyle())

            Text("只清理曲库中指向已丢失文件的记录，不会删除仍存在的歌曲。")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "关于 PureTune", systemImage: "music.note", tint: AppTheme.ice) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accentGradient)
                        .frame(width: 52, height: 52)

                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.primaryButtonText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("PureTune 纯音")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("版本 \(versionText)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textTertiary)
                }

                Spacer()
            }

            Text("完全本地播放 · 无账号 · 无广告 · 无会员 · 不上传音乐与播放记录")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text("界面使用系统 Material 与自适应光影构建玻璃层级；在支持原生 Liquid Glass 的新系统上继续沿用系统材质能力，旧系统使用等价的 SwiftUI 降级方案。")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
                .lineSpacing(2)
        }
    }

    private var resetCard: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 19, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("恢复默认设置")
                        .font(.subheadline.weight(.semibold))

                    Text("不会删除歌曲或曲库数据")
                        .font(.caption2)
                        .opacity(0.7)
                }

                Spacer()
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(17)
            .glassPanel(cornerRadius: 22, tint: AppTheme.warm, strokeOpacity: 0.12)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var audioSummary: String {
        let eq = settings.equalizerEnabled ? "EQ 开" : "EQ 关"
        let fade = settings.fadeOption == .off ? "无淡入淡出" : "淡入淡出 \(settings.fadeOption.title)"
        return "\(eq) · \(settings.playbackRate.title) · \(fade)"
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "2.1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "3"
        return "\(version) (\(build))"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            content
        }
        .padding(18)
        .glassPanel(cornerRadius: 27, tint: tint, strokeOpacity: 0.14)
    }
}

private struct LibraryStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.hairline.opacity(0.4), lineWidth: 0.6)
        }
    }
}
