import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var audio: AudioPlayer

    @State private var showingPicker = false
    @State private var showingNowPlaying = false
    @State private var searchText = ""
    @State private var songToDelete: Song?
    @State private var showingDeleteConfirmation = false
    @State private var sortMode: LibrarySort = .title
    @State private var pendingPickedURLs: [URL] = []
    @State private var pickerReturnedNoFiles = false

    private var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty
            ? library.songs
            : library.songs.filter {
                $0.searchableText.localizedCaseInsensitiveContains(query)
            }

        switch sortMode {
        case .title:
            return matches.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .recentlyAdded:
            return matches.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(spacing: 0) {
                    header
                    searchBar
                    mainContent
                }

                if library.isImporting {
                    importingOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if audio.currentSong != nil {
                    MiniPlayerView(onOpen: { showingNowPlaying = true })
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert(item: $library.importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("好"))
                )
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
            .sheet(
                isPresented: $showingPicker,
                onDismiss: processPendingPickedFiles
            ) {
                DocumentPicker(
                    onPick: queuePickedFiles,
                    onCancel: { showingPicker = false }
                )
                .ignoresSafeArea()
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingNowPlaying) {
                NowPlayingView()
                    .environmentObject(audio)
            }
            .onChange(of: library.songs) { songs in
                audio.updateQueue(songs) { song in
                    library.fileURL(for: song)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: library.isImporting)
        }
        .tint(.white)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("纯音")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text(librarySubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            sortMenu

            GlassIconButton(
                systemName: "plus",
                label: "导入音乐",
                size: 48,
                action: { showingPicker = true }
            )
            .disabled(library.isImporting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private var librarySubtitle: String {
        if library.songs.isEmpty {
            return "完全离线 · 只属于你的音乐"
        }

        let totalDuration = library.songs.reduce(0) { $0 + $1.duration }
        return "\(library.songs.count) 首歌曲 · \(totalDurationText(totalDuration))"
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySort.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sortMode = mode
                    }
                } label: {
                    if sortMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .accessibilityLabel("排序方式")
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            TextField("搜索歌曲、歌手或专辑", text: $searchText)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .glassPanel(cornerRadius: 17, strokeOpacity: 0.1)
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private var mainContent: some View {
        if library.songs.isEmpty {
            emptyState
        } else if filteredSongs.isEmpty {
            noResults
        } else {
            songList
        }
    }

    private var songList: some View {
        List {
            ForEach(filteredSongs) { song in
                Button {
                    play(song)
                } label: {
                    SongRow(
                        song: song,
                        isCurrent: audio.currentSong?.id == song.id,
                        isPlaying: audio.isPlaying
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        songToDelete = song
                        showingDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(Color(red: 0.94, green: 0.29, blue: 0.34))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 28)

            VStack(spacing: 21) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.ice.opacity(0.35),
                                    AppTheme.lavender.opacity(0.17)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .blur(radius: 0.2)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        .frame(width: 104, height: 104)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(spacing: 9) {
                    Text("把音乐留在本机")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text("从「文件」导入音频，自动复制到本地曲库。\n无需登录、无需联网，也不会上传任何内容。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Button {
                    showingPicker = true
                } label: {
                    Label("导入音乐", systemImage: "plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(library.isImporting)

                Text("支持系统可解码的 MP3、AAC/M4A、WAV、AIFF、FLAC 等格式")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .glassPanel(cornerRadius: 32, tint: AppTheme.ice, strokeOpacity: 0.2)
            .padding(.horizontal, 22)

            Spacer(minLength: 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.36))

            Text("没有找到相关歌曲")
                .font(.headline)

            Text("试试搜索歌曲名、歌手或专辑")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ice.opacity(0.14))
                        .frame(width: 52, height: 52)

                    ProgressView()
                        .tint(AppTheme.ice)
                        .scaleEffect(1.1)
                }

                Text("正在导入音乐")
                    .font(.headline)

                if let progress = library.importProgress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.ice)
                        .frame(width: 190)

                    Text(progress.fileName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .frame(maxWidth: 220)

                    Text(progress.statusText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.32))
                } else {
                    Text("正在准备文件")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 25)
            .glassPanel(cornerRadius: 28, tint: AppTheme.ice, strokeOpacity: 0.22)
        }
    }

    private func queuePickedFiles(_ urls: [URL]) {
        pendingPickedURLs = urls
        pickerReturnedNoFiles = urls.isEmpty
        showingPicker = false
    }

    private func processPendingPickedFiles() {
        if pickerReturnedNoFiles {
            pickerReturnedNoFiles = false
            pendingPickedURLs = []
            library.reportEmptySelection()
            return
        }

        guard !pendingPickedURLs.isEmpty else { return }
        let urls = pendingPickedURLs
        pendingPickedURLs = []

        Task { @MainActor in
            await library.importFiles(urls)
        }
    }

    private func play(_ song: Song) {
        audio.play(song: song, from: filteredSongs) { song in
            library.fileURL(for: song)
        }
    }

    private func totalDurationText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 分钟" }
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
        }
        return "\(max(minutes, 1)) 分钟"
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case title
    case recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            return "按标题排序"
        case .recentlyAdded:
            return "最近添加优先"
        }
    }
}
