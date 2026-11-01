import SwiftUI

@main
struct PureTuneApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var audioPlayer = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(audioPlayer)
                .preferredColorScheme(.dark)
        }
    }
}
