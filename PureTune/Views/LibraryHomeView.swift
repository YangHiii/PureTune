import SwiftUI

struct LibraryHomeView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var audio: AudioPlayer

    let onImport: () -> Void
    let onOpenSearch: () -> Void

    @State private var scope: LibraryScope = .songs
    @State private var layout: LibraryLayout = .list
    @State private var selectedCollection: SongCollection?
    @State private var songToDelete: Song?
    @State private var showingDeleteConfirmation = false

    private var recentPlayed: [Song] {
        Array(library.recentlyPlayedSongs.prefix(8))
    }

    private var recentAdded: [Song] {
        Array(
            library.songs
                .sorted { $0.dateAdded > $1.dateAdded }
                .prefix(8)
        )
    }

    private var albumCollections: [SongCollection] {
        Dictionary(grouping: library.songs, by: \.displayAlbum)
            .map { title, songs in
                SongCollection(
                    id: "album-\(title)",
                    title: title,
                    subtitle: "\(songs.count) 首歌曲",
                    systemImage: "rectangle.stack.fill",
                    songs: songs.sorted(by: songTitleSort)
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var artistCollections: [SongCollection] {
        Dictionary(grouping: library.songs, by: \.displayArtist)
            .map { name, songs in
                SongCollection(
                    id: "artist-\(name)",
                    title: name,
                    subtitle: "\(Set(songs.map(\.displayAlbum)).count) 张专辑",
                    systemImage: "person.fill",
                    songs: songs.sorted(by: songTitleSort)
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                searchEntry

                if library.songs.isEmpty {
                    emptyLibrary
                } else {
                    if !recentPlayed.isEmpty {
                        recentPlayedSection
                    }

                    if !recentAdded.isEmpty {
                        recentAddedSection
                    }

                    musicSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedCollection) { collection in
            CollectionSongsView(collection: collection)
        }
        .confirmationDialog(
            "删除「\(songToDelete?.title ?? "这首歌曲")」？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let song = songToDelete else { return }
                if library.delete(song) {
                    audio.removeFromQueue(song)
                }
                songToDelete = nil
            }

            Button("取消", role: .cancel) {
                songToDelete = nil
            }
        } message: {
            Text("将同时从本机音乐库中移除此文件，无法撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PURE TUNE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(3.2)
                    .foregroundStyle(AppTheme.ice)

                Text("纯音")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(librarySubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            GlassIconButton(
                systemName: "plus",
                label: "导入音乐",
                size: 48,
                action: onImport
            )
            .disabled(library.isImporting)
        }
    }

    private var searchEntry: some View {
        Button(action: onOpenSearch) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)

                Text("搜索歌曲、专辑或艺术家")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
            }
            .padding(.horizontal, 15)
            .frame(height: 48)
            .glassPanel(cornerRadius: 17, tint: AppTheme.ice, strokeOpacity: 0.1)
        }
        .buttonStyle(.plain)
    }

    private var recentPlayedSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "最近播放",
                subtitle: "从上次停下的地方继续"
            )

            ScrollView(.horizontal) {
                LazyHStack(spacing: 13) {
                    ForEach(recentPlayed) { song in
                        RecentSongCard(
                            song: song,
                            fileURL: library.fileURL(for: song),
                            isCurrent: audio.currentSong?.id == song.id,
                            isPlaying: audio.isPlaying
                        ) {
                            play(song, from: recentPlayed)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var recentAddedSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "最近添加",
                subtitle: "新加入本机曲库的音乐"
            )

            ScrollView(.horizontal) {
                LazyHStack(spacing: 13) {
                    ForEach(recentAdded) { song in
                        RecentSongCard(
                            song: song,
                            fileURL: library.fileURL(for: song),
                            isCurrent: audio.currentSong?.id == song.id,
                            isPlaying: audio.isPlaying
                        ) {
                            play(song, from: recentAdded)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "你的音乐",
                subtitle: musicSectionSubtitle
            )

            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(LibraryScope.allCases) { item in
                            ScopeChip(
                                title: item.title,
                                isSelected: scope == item
                            ) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    scope = item
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if scope == .songs {
                    layoutToggle
                }
            }

            switch scope {
            case .songs:
                songContent
            case .albums:
                collectionGrid(albumCollections)
            case .artists:
                collectionGrid(artistCollections)
            }
        }
    }

    private var layoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                layout = layout == .list ? .grid : .list
            }
        } label: {
            Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 38, height: 34)
                .background(AppTheme.controlFill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.hairline.opacity(0.7), lineWidth: 0.7)
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(layout == .list ? "切换网格" : "切换列表")
    }

    @ViewBuilder
    private var songContent: some View {
        switch layout {
        case .list:
            LazyVStack(spacing: 10) {
                ForEach(library.songs) { song in
                    SongRow(
                        song: song,
                        fileURL: library.fileURL(for: song),
                        isCurrent: audio.currentSong?.id == song.id,
                        isPlaying: audio.isPlaying,
                        onDelete: { requestDelete(song) }
                    )
                    .onTapGesture {
                        play(song, from: library.songs)
                    }
                    .accessibilityAddTraits(.isButton)
                }
            }
        case .grid:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 146), spacing: 14)],
                spacing: 14
            ) {
                ForEach(library.songs) { song in
                    SongGridCard(
                        song: song,
                        fileURL: library.fileURL(for: song),
                        isCurrent: audio.currentSong?.id == song.id,
                        isPlaying: audio.isPlaying
                    ) {
                        play(song, from: library.songs)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            requestDelete(song)
                        } label: {
                            Label("从曲库删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func collectionGrid(_ collections: [SongCollection]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 146), spacing: 14)],
            spacing: 14
        ) {
            ForEach(collections) { collection in
                CollectionCard(collection: collection, library: library) {
                    selectedCollection = collection
                }
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.ice.opacity(0.38),
                                AppTheme.lavender.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Circle()
                    .strokeBorder(AppTheme.hairline.opacity(0.6), lineWidth: 0.8)
                    .frame(width: 108, height: 108)

                Image(systemName: "music.note.list")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
            }

            VStack(spacing: 9) {
                Text("把音乐留在本机")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("从「文件」导入音频，自动复制到本地曲库。\n无需登录、无需联网，也不会上传任何内容。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button(action: onImport) {
                Label("导入音乐", systemImage: "plus")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(library.isImporting)

            Text("支持系统可解码的 MP3、AAC/M4A、WAV、AIFF、FLAC 等格式")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary.opacity(0.74))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 32)
        .frame(maxWidth: 560)
        .glassPanel(cornerRadius: 32, tint: AppTheme.ice, strokeOpacity: 0.2)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var librarySubtitle: String {
        guard !library.songs.isEmpty else {
            return "完全离线 · 只属于你的音乐"
        }

        let duration = library.songs.reduce(0) { $0 + $1.duration }
        return "\(library.songs.count) 首歌曲 · \(durationText(duration)) · \(storageText)"
    }

    private var musicSectionSubtitle: String {
        switch scope {
        case .songs:
            return "\(library.songs.count) 首歌曲"
        case .albums:
            return "\(albumCollections.count) 张专辑"
        case .artists:
            return "\(artistCollections.count) 位艺术家"
        }
    }

    private var storageText: String {
        ByteCountFormatter.string(fromByteCount: library.totalFileSize, countStyle: .file)
    }

    private func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 分钟" }
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
        }
        return "\(max(minutes, 1)) 分钟"
    }

    private func play(_ song: Song, from songs: [Song]) {
        audio.play(song: song, from: songs) { item in
            library.fileURL(for: item)
        }
    }

    private func requestDelete(_ song: Song) {
        songToDelete = song
        showingDeleteConfirmation = true
    }
}

struct SongCollection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let songs: [Song]
}

private enum LibraryScope: String, CaseIterable, Identifiable {
    case songs
    case albums
    case artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:
            return "歌曲"
        case .albums:
            return "专辑"
        case .artists:
            return "艺术家"
        }
    }
}

private enum LibraryLayout {
    case list
    case grid
}

private func songTitleSort(_ lhs: Song, _ rhs: Song) -> Bool {
    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}

private struct ScopeChip: View {
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
                        Capsule()
                            .fill(AppTheme.accentGradient)
                    } else {
                        Capsule()
                            .fill(AppTheme.controlFill)
                    }
                }
                .overlay {
                    Capsule()
                        .stroke(AppTheme.hairline.opacity(0.55), lineWidth: 0.7)
                }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct RecentSongCard: View {
    let song: Song
    let fileURL: URL
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ArtworkView(
                    song: song,
                    url: fileURL,
                    cornerRadius: 18,
                    isCurrent: isCurrent,
                    isPlaying: isPlaying,
                    showsPlaybackBadge: true
                )
                .frame(width: 148, height: 148)

                Text(song.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(song.displayArtist)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct SongGridCard: View {
    let song: Song
    let fileURL: URL
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ArtworkView(
                    song: song,
                    url: fileURL,
                    cornerRadius: 18,
                    isCurrent: isCurrent,
                    isPlaying: isPlaying,
                    showsPlaybackBadge: true
                )
                .aspectRatio(1, contentMode: .fit)

                Text(song.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(song.displayArtist)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .glassPanel(
                cornerRadius: 22,
                tint: isCurrent ? AppTheme.ice : .clear,
                strokeOpacity: isCurrent ? 0.22 : 0.1
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct CollectionCard: View {
    let collection: SongCollection
    let library: MusicLibrary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                if let first = collection.songs.first {
                    ArtworkView(
                        song: first,
                        url: library.fileURL(for: first),
                        cornerRadius: 18
                    )
                    .aspectRatio(1, contentMode: .fit)
                }

                Text(collection.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(collection.subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .glassPanel(cornerRadius: 22, strokeOpacity: 0.1)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct CollectionSongsView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var audio: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    let collection: SongCollection

    @State private var songToDelete: Song?
    @State private var showingDeleteConfirmation = false

    private var songs: [Song] {
        collection.songs.filter { song in
            library.songs.contains { $0.id == song.id }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(collection.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Text("\(songs.count) 首歌曲")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textTertiary)
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
                .padding(.top, 12)
                .padding(.bottom, 10)

                if let first = songs.first {
                    Button {
                        audio.play(song: first, from: songs) { song in
                            library.fileURL(for: song)
                        }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .padding(.bottom, 12)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(songs) { song in
                            SongRow(
                                song: song,
                                fileURL: library.fileURL(for: song),
                                isCurrent: audio.currentSong?.id == song.id,
                                isPlaying: audio.isPlaying,
                                onDelete: {
                                    songToDelete = song
                                    showingDeleteConfirmation = true
                                }
                            )
                            .onTapGesture {
                                audio.play(song: song, from: songs) { item in
                                    library.fileURL(for: item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "删除「\(songToDelete?.title ?? "这首歌曲")」？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let song = songToDelete else { return }
                if library.delete(song) {
                    audio.removeFromQueue(song)
                }
                songToDelete = nil
            }

            Button("取消", role: .cancel) {
                songToDelete = nil
            }
        }
    }
}
