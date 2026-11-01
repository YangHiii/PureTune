import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var audio: AudioPlayer

    @State private var showingImporter = false
    @State private var showingNowPlaying = false
    @State private var searchText = ""
    @State private var songToDelete: Song?
    @State private var showingDeleteConfirmation = false

    private var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.songs }

        return library.songs.filter {
            $0.searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                if library.songs.isEmpty {
                    emptyLibrary
                } else {
                    songCollection
                }
            }
            .navigationTitle("纯音")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(library.isImporting)
                    .accessibilityLabel("导入音乐")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if audio.currentSong != nil {
                    MiniPlayerView(onOpen: { showingNowPlaying = true })
                }
            }
            .overlay {
                if library.isImporting {
                    importingOverlay
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleImportResult(result)
            }
            .sheet(isPresented: $showingNowPlaying) {
                NowPlayingView()
                    .environmentObject(audio)
            }
        }
        .tint(.white)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.09, blue: 0.12),
                Color(red: 0.035, green: 0.04, blue: 0.055)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
                .padding(24)
                .background(Color.white.opacity(0.06), in: Circle())

            VStack(spacing: 8) {
                Text("把音乐留在本机")
                    .font(.title3.bold())

                Text("从 iPhone「文件」App 导入音频。\n无需登录、无需联网，也不会上传任何内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                showingImporter = true
            } label: {
                Label("导入音乐", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(library.isImporting)
            .padding(.top, 4)

            Text("支持系统可解码的 MP3、AAC/M4A、WAV、AIFF 等格式")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var songCollection: some View {
        Group {
            if filteredSongs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("没有找到相关歌曲")
                        .font(.headline)
                    Text("试试搜索歌曲名、歌手或专辑")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                            EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                songToDelete = song
                                showingDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索歌曲、歌手或专辑"
        )
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)

                Text("正在导入音乐")
                    .font(.subheadline.weight(.medium))

                Text("文件会复制到本机音乐库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .transition(.opacity)
    }

    private func play(_ song: Song) {
        audio.play(song: song, from: filteredSongs) { song in
            library.fileURL(for: song)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { @MainActor in
                await library.importFiles(urls)
            }
        case .failure(let error):
            library.presentImportError(error)
        }
    }
}
