import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackError: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []

    private var queue: [Song] = []
    private var currentIndex = 0
    private var currentURLProvider: ((Song) -> URL)?
    private var shouldResumeAfterInterruption = false

    init() {
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSession()
    }

    func play(song: Song, from songs: [Song], urlProvider: @escaping (Song) -> URL) {
        queue = songs
        currentURLProvider = urlProvider

        if currentSong?.id == song.id, player != nil {
            currentIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
            if !isPlaying {
                resume()
            }
            return
        }

        guard let index = queue.firstIndex(where: { $0.id == song.id }) else { return }
        currentIndex = index
        loadCurrentSong(autoplay: true)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard let player, currentSong != nil else { return }

        activateAudioSession()
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }

        let upperBound = duration > 0 ? duration : max(currentTime, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        loadCurrentSong(autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }

        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadCurrentSong(autoplay: true)
    }

    func removeFromQueue(_ song: Song) {
        let wasCurrent = currentSong?.id == song.id
        let removedIndex = queue.firstIndex(where: { $0.id == song.id })
        let wasPlaying = isPlaying

        queue.removeAll { $0.id == song.id }

        if queue.isEmpty {
            stop()
            return
        }

        if wasCurrent {
            if let removedIndex {
                currentIndex = min(removedIndex, queue.count - 1)
            } else {
                currentIndex = 0
            }
            loadCurrentSong(autoplay: wasPlaying)
        } else {
            currentIndex = queue.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
            updateRemoteCommandAvailability()
        }
    }

    func stop() {
        teardownCurrentPlayer()
        queue = []
        currentIndex = 0
        currentSong = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommandAvailability()

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    func clearPlaybackError() {
        playbackError = nil
    }

    private func loadCurrentSong(autoplay: Bool) {
        guard queue.indices.contains(currentIndex),
              let currentURLProvider else {
            stop()
            return
        }

        teardownCurrentPlayer()

        let song = queue[currentIndex]
        let url = currentURLProvider(song)
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        currentSong = song
        player = newPlayer
        currentTime = 0
        duration = song.duration
        playbackError = nil

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
        }

        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
            [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }

            let message = observedItem.error?.localizedDescription
                ?? "音频文件无法播放。"
            Task { @MainActor [weak self] in
                guard let self,
                      self.currentSong?.id == song.id else {
                    return
                }
                self.isPlaying = false
                self.playbackError = message
                self.updateNowPlayingInfo()
            }
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleTimeUpdate(time)
            }
        }

        if autoplay {
            activateAudioSession()
            newPlayer.play()
        }

        isPlaying = autoplay
        updateNowPlayingInfo()
        updateRemoteCommandAvailability()

        Task { @MainActor [weak self] in
            let asset = AVURLAsset(url: url)
            guard let loadedDuration = try? await asset.load(.duration) else { return }
            guard let self, self.currentSong?.id == song.id else { return }

            let seconds = CMTimeGetSeconds(loadedDuration)
            if seconds.isFinite, seconds > 0 {
                self.duration = seconds
                self.updateNowPlayingInfo()
            }
        }
    }

    private func handleTimeUpdate(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return }

        currentTime = max(0, seconds)

        if let itemDuration = player?.currentItem?.duration {
            let loadedDuration = CMTimeGetSeconds(itemDuration)
            if loadedDuration.isFinite, loadedDuration > 0 {
                duration = loadedDuration
            }
        }

        updateNowPlayingInfo()
    }

    private func teardownCurrentPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        itemEndObserver = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        player?.pause()
        player = nil
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []
            )
        } catch {
            playbackError = "音频会话配置失败：\(error.localizedDescription)"
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackError = "无法启用音频播放：\(error.localizedDescription)"
        }
    }

    private func observeAudioSession() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            if isPlaying {
                pause()
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if shouldResumeAfterInterruption, options.contains(.shouldResume) {
                resume()
            }
            shouldResumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }

        if reason == .oldDeviceUnavailable, isPlaying {
            pause()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.target)
        }
        remoteCommandTargets.removeAll()

        remoteCommandTargets.append((
            center.playCommand,
            center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.resume() }
                return .success
            }
        ))

        remoteCommandTargets.append((
            center.pauseCommand,
            center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
                return .success
            }
        ))

        remoteCommandTargets.append((
            center.togglePlayPauseCommand,
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.togglePlayback() }
                return .success
            }
        ))

        remoteCommandTargets.append((
            center.nextTrackCommand,
            center.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.next() }
                return .success
            }
        ))

        remoteCommandTargets.append((
            center.previousTrackCommand,
            center.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in self?.previous() }
                return .success
            }
        ))

        remoteCommandTargets.append((
            center.changePlaybackPositionCommand,
            center.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor [weak self] in
                    self?.seek(to: positionEvent.positionTime)
                }
                return .success
            }
        ))

        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let hasContent = currentSong != nil

        center.playCommand.isEnabled = hasContent
        center.pauseCommand.isEnabled = hasContent
        center.togglePlayPauseCommand.isEnabled = hasContent
        center.nextTrackCommand.isEnabled = hasContent
        center.previousTrackCommand.isEnabled = hasContent
        center.changePlaybackPositionCommand.isEnabled = hasContent && duration > 0
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            updateRemoteCommandAvailability()
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(currentTime, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        updateRemoteCommandAvailability()
    }
}
