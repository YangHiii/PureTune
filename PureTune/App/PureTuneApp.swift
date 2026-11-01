import SwiftUI

@main
struct PureTuneApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var library = MusicLibrary()
    @StateObject private var audioPlayer: AudioPlayer

    init() {
        let settings = SettingsManager()
        _settingsManager = StateObject(wrappedValue: settings)
        _audioPlayer = StateObject(wrappedValue: AudioPlayer(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(audioPlayer)
                .environmentObject(audioPlayer.clock)
                .environmentObject(settingsManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.mode.colorScheme)
        }
    }
}
