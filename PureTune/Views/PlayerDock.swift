import SwiftUI

struct PlayerDock: View {
    @EnvironmentObject private var audio: AudioPlayer
    @EnvironmentObject private var library: MusicLibrary

    @Binding var selectedTab: AppTab
    @State private var showingNowPlaying = false

    var body: some View {
        VStack(spacing: 8) {
            if audio.currentSong != nil {
                MiniPlayerView {
                    showingNowPlaying = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassTabBar(selection: $selectedTab)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: audio.currentSong?.id)
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView {
                showingNowPlaying = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    selectedTab = .effects
                }
            }
        }
        .onAppear {
            audio.onSongStarted = { song in
                library.markPlayed(song)
            }
            audio.updateQueue(library.songs) { song in
                library.fileURL(for: song)
            }
        }
        .onChange(of: library.songs) { songs in
            audio.updateQueue(songs) { song in
                library.fileURL(for: song)
            }
        }
        .onChange(of: audio.currentSong?.id) { songID in
            if songID == nil {
                showingNowPlaying = false
            }
        }
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
