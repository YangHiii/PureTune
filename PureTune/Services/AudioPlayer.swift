import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var queueCount = 0
    @Published private(set) var queuePosition = 0
    @Published private(set) var playbackError: String?

    var queuePositionText: String {
        guard queueCount > 0, queuePosition > 0 else { return "" }
        return "\(queuePosition) / \(queueCount)"
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var durationTask: Task<Void, Never>?

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
        let newQueue = songs.isEmpty ? [song] : songs
        guard let index = newQueue.firstIndex(where: { $0.id == song.id }) else {
            return
        }

        queue = newQueue
        currentURLProvider = urlProvider
        queueCount = queue.count

        if currentSong?.id == song.id, player != nil {
            currentIndex = index
            queuePosition = index + 1
            if !isPlaying {
                resume()
            } else {
                updateNowPlayingInfo()
            }
            return
        }

        currentIndex = index
        queuePosition = index + 1
        loadCurrentSong(autoplay: true)
    }

    func updateQueue(
        _ songs: [Song],
        urlProvider: @escaping (Song) -> URL
    ) {
        currentURLProvider = urlProvider
        queue = songs
        queueCount = songs.count

        guard let currentSong else {
            queuePosition = 0
            return
        }

        guard let index = songs.firstIndex(where: { $0.id == currentSong.id }) else {
            stop()
            return
        }

        currentIndex = index
        queuePosition = index + 1
        updateRemoteCommandAvailability()
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
        queuePosition = currentIndex + 1
        loadCurrentSong(autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }

        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        queuePosition = currentIndex + 1
        loadCurrentSong(autoplay: true)
    }

    func removeFromQueue(_ song: Song) {
        let wasCurrent = currentSong?.id == song.id
        let removedIndex = queue.firstIndex(where: { $0.id == song.id })
        let wasPlaying = isPlaying

        queue.removeAll { $0.id == song.id }
        queueCount = queue.count

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
            queuePosition = currentIndex + 1
            loadCurrentSong(autoplay: wasPlaying)
        } else {
            currentIndex = queue.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
            queuePosition = currentIndex + 1
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
        queueCount = 0
        queuePosition = 0
        playbackError = nil
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

        currentSong = song
        currentTime = 0
        duration = song.duration
        queueCount = queue.count
        queuePosition = currentIndex + 1
        playbackError = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            isPlaying = false
            playbackError = "找不到「\(song.title)」的音频文件，可能已被移动或删除。"
            updateNowPlayingInfo()
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
        }

        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
                ?? "播放过程中发生未知错误。"

            Task { @MainActor [weak self] in
                guard let self, self.currentSong?.id == song.id else { return }
                self.isPlaying = false
                self.playbackError = message
                self.updateNowPlayingInfo()
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

        timeControlObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) {
            [weak self, weak newPlayer] observedPlayer, _ in
            let status = observedPlayer.timeControlStatus

            Task { @MainActor [weak self, weak newPlayer] in
                guard let self,
                      let newPlayer,
                      self.player === newPlayer else {
                    return
                }

                let playing = status != .paused
                if self.isPlaying != playing {
                    self.isPlaying = playing
                    self.updateNowPlayingInfo()
                }
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

        durationTask = Task { @MainActor [weak self] in
            let asset = AVURLAsset(url: url)
            guard let loadedDuration = try? await asset.load(.duration) else { return }
            guard !Task.isCancelled,
                  let self,
                  self.currentSong?.id == song.id else {
                return
            }

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
        durationTask?.cancel()
        durationTask = nil

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        itemEndObserver = nil

        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
        }
        itemFailureObserver = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        timeControlObservation?.invalidate()
        timeControlObservation = nil

        player?.pause()
        player = nil
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay]
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

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.configureAudioSession()
                self.configureRemoteCommands()
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
        center.nextTrackCommand.isEnabled = hasContent && queueCount > 1
        center.previousTrackCommand.isEnabled = hasContent && queueCount > 1
        center.changePlaybackPositionCommand.isEnabled = hasContent && duration > 0
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            updateRemoteCommandAvailability()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(currentTime, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if queueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }
}
