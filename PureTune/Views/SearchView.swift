import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var audio: AudioPlayer

    @State private var query = ""
    @State private var songToDelete: Song?
    @State private var showingDeleteConfirmation = false
    @FocusState private var searchFocused: Bool

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Song] {
        let matched: [Song]
        if normalizedQuery.isEmpty {
            matched = library.songs
        } else {
            matched = library.songs.filter {
                $0.searchableText.localizedCaseInsensitiveContains(normalizedQuery)
            }
        }

        return matched.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                searchField

                if library.songs.isEmpty {
                    emptyState
                } else if results.isEmpty {
                    noResults
                } else {
                    resultHeader

                    LazyVStack(spacing: 10) {
                        ForEach(results) { song in
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
                                play(song)
                            }
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 26)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
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
        VStack(alignment: .leading, spacing: 5) {
            Text("SEARCH")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(3.2)
                .foregroundStyle(AppTheme.lavender)

            Text("搜索")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("在完全本地的曲库中查找歌曲、专辑或艺术家")
                .font(.caption)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            TextField("输入关键词", text: $query)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .glassPanel(cornerRadius: 18, tint: AppTheme.lavender, strokeOpacity: 0.13)
    }

    private var resultHeader: some View {
        HStack {
            Text(normalizedQuery.isEmpty ? "全部歌曲" : "搜索结果")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Text("\(results.count) 首")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)

            Text("曲库还是空的")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("回到音乐库导入音乐后，就可以在这里搜索。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .glassPanel(cornerRadius: 26, strokeOpacity: 0.1)
    }

    private var noResults: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppTheme.textTertiary)

            Text("没有找到相关歌曲")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("试试更短的歌曲名、艺术家或专辑关键词。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private func play(_ song: Song) {
        let queue = results
        audio.play(song: song, from: queue) { item in
            library.fileURL(for: item)
        }
    }
}
