import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var queueCount = 0
    @Published private(set) var queuePosition = 0
    @Published private(set) var playbackError: String?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var currentSourceInfo: AudioSourceInfo?
    @Published private(set) var currentNormalizationGainDB: Float = 0

    let clock = PlaybackClock()
    var onSongStarted: ((Song) -> Void)?

    var queuePositionText: String {
        guard queueCount > 0, queuePosition > 0 else { return "" }
        return "\(queuePosition) / \(queueCount)"
    }

    func artwork(for song: Song) -> UIImage? {
        guard currentArtworkSongID == song.id else { return nil }
        return currentArtwork
    }

    private let settings: SettingsManager
    private var engine = AVAudioEngine()
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let transitionMixer = AVAudioMixerNode()
    private let equalizer = EqualizerManager()
    private let normalizationNode = AVAudioUnitEQ(numberOfBands: 1)
    private let timePitchNode = AVAudioUnitTimePitch()

    private var queue: [Song] = []
    private var currentIndex = 0
    private var currentURLProvider: ((Song) -> URL)?
    private var activeNode: AVAudioPlayerNode?
    private var currentFile: AVAudioFile?
    private var currentArtworkSongID: UUID?
    private var currentSampleRate: Double = 48_000
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var playbackGeneration = 0
    private var engineConfigured = false

    private var cancellables: Set<AnyCancellable> = []
    private var fadeTasks: [Task<Void, Never>] = []
    private var normalizationRampTask: Task<Void, Never>?
    private var normalizationTask: Task<Void, Never>?
    private var informationTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var normalizationCache: [String: Float] = [:]
    private var nowPlayingArtwork: MPMediaItemArtwork?

    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    private var shouldResumeAfterRouteChange = false
    private var clockCancellable: AnyCancellable?
    private var audioSessionConfigured = false
    private var appIsActive = true

    init(settings: SettingsManager) {
        self.settings = settings

        configureEngine()
        configureNormalizationNode()
        configureRemoteCommands()
        observeAudioSession()
        observeAppLifecycle()
        bindSettings()
        bindPlaybackClock()
        updateClockSubscription()

        applyEqualizerSettings(animated: false)
        applyNormalizationGain(0, animated: false)
        timePitchNode.rate = settings.playbackRateValue
        engine.mainMixerNode.outputVolume = Float(settings.appVolume)
    }

    func play(song: Song, from songs: [Song], urlProvider: @escaping (Song) -> URL) {
        let newQueue = songs.isEmpty ? [song] : songs
        guard let index = newQueue.firstIndex(where: { $0.id == song.id }) else {
            return
        }

        queue = newQueue
        queueCount = queue.count
        currentIndex = index
        queuePosition = index + 1
        currentURLProvider = urlProvider

        if currentSong?.id == song.id, currentFile != nil {
            if !isPlaying {
                resume()
            } else {
                updateNowPlayingInfo()
            }
            return
        }

        startTrack(song, at: 0, autoplay: true, markPlayed: true)
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
            guard !songs.isEmpty else {
                stop()
                return
            }

            let wasPlaying = isPlaying
            currentIndex = min(max(currentIndex, 0), songs.count - 1)
            queuePosition = currentIndex + 1
            startTrack(
                songs[currentIndex],
                at: 0,
                autoplay: wasPlaying,
                markPlayed: wasPlaying
            )
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
        guard let song = currentSong else { return }

        guard let node = activeNode, currentFile != nil else {
            startTrack(song, at: clock.time, autoplay: true, markPlayed: false)
            return
        }

        if duration > 0, clock.time >= duration - 0.15 {
            startTrack(song, at: 0, autoplay: true, markPlayed: false)
            return
        }

        guard activateAudioSession() else {
            isPlaying = false
            return
        }
        guard startEngineIfNeeded() else { return }

        node.volume = 1
        node.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        guard isPlaying else { return }

        cancelFades()
        for node in [playerA, playerB] where node !== activeNode {
            node.stop()
            node.volume = 0
        }

        activeNode?.volume = 1
        activeNode?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        guard let song = currentSong,
              let file = currentFile,
              let node = activeNode,
              seconds.isFinite else {
            return
        }

        let target = min(max(seconds, 0), max(duration, 0))
        let wasPlaying = isPlaying

        cancelFades()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        node.stop()

        if duration > 0, target >= duration - 0.05 {
            clock.update(duration)
            isPlaying = false
            engine.pause()
            updateNowPlayingInfo()
            return
        }

        let startFrame = AVAudioFramePosition(target * currentSampleRate)
        segmentStartFrame = min(max(startFrame, 0), file.length)
        clock.update(target)
        schedule(file: file, on: node, startFrame: segmentStartFrame, songID: song.id, generation: generation)

        if wasPlaying {
            guard activateAudioSession(), startEngineIfNeeded() else {
                isPlaying = false
                return
            }
            node.volume = 1
            node.play()
            isPlaying = true
        } else {
            node.volume = 1
            isPlaying = false
        }

        updateNowPlayingInfo()
    }

    func next() {
        guard !queue.isEmpty else { return }

        if settings.playbackMode == .shuffle, queue.count > 1 {
            currentIndex = randomIndex(excluding: currentIndex)
        } else {
            currentIndex = (currentIndex + 1) % queue.count
        }

        queuePosition = currentIndex + 1
        startTrack(queue[currentIndex], at: 0, autoplay: true, markPlayed: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if clock.time > 3 {
            seek(to: 0)
            return
        }

        if settings.playbackMode == .shuffle, queue.count > 1 {
            currentIndex = randomIndex(excluding: currentIndex)
        } else {
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
        }

        queuePosition = currentIndex + 1
        startTrack(queue[currentIndex], at: 0, autoplay: true, markPlayed: true)
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
            currentIndex = min(removedIndex ?? 0, queue.count - 1)
            queuePosition = currentIndex + 1
            startTrack(
                queue[currentIndex],
                at: 0,
                autoplay: wasPlaying,
                markPlayed: wasPlaying
            )
        } else {
            currentIndex = queue.firstIndex(where: { $0.id == currentSong?.id }) ?? 0
            queuePosition = currentIndex + 1
            updateRemoteCommandAvailability()
        }
    }

    func stop() {
        playbackGeneration &+= 1
        cancelFades()
        normalizationRampTask?.cancel()
        normalizationTask?.cancel()
        informationTask?.cancel()
        artworkTask?.cancel()

        playerA.stop()
        playerB.stop()
        playerA.volume = 0
        playerB.volume = 0
        activeNode = nil
        currentFile = nil

        queue = []
        currentIndex = 0
        currentURLProvider = nil
        currentSong = nil
        currentArtwork = nil
        currentArtworkSongID = nil
        currentSourceInfo = nil
        currentNormalizationGainDB = 0
        nowPlayingArtwork = nil
        isPlaying = false
        duration = 0
        queueCount = 0
        queuePosition = 0
        playbackError = nil
        clock.reset()

        engine.pause()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommandAvailability()
        deactivateAudioSession()
    }

    func clearPlaybackError() {
        playbackError = nil
    }

    private func startTrack(
        _ song: Song,
        at seconds: Double,
        autoplay: Bool,
        markPlayed: Bool
    ) {
        guard let urlProvider = currentURLProvider else { return }
        let url = urlProvider(song)

        guard let file = try? AVAudioFile(forReading: url) else {
            playbackError = "找不到或无法读取「\(song.title)」的音频文件。"
            return
        }

        let sampleRate = file.processingFormat.sampleRate
        let trackDuration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

        guard sampleRate > 0, trackDuration > 0 else {
            playbackError = "「\(song.title)」没有可播放的音频帧。"
            return
        }

        cancelFades()
        playbackGeneration &+= 1
        let generation = playbackGeneration
        let oldNode = activeNode
        let newNode: AVAudioPlayerNode = oldNode === playerA ? playerB : playerA

        for node in [playerA, playerB] where node !== oldNode && node !== newNode {
            node.stop()
            node.volume = 0
        }

        newNode.stop()
        newNode.volume = 0
        configurePlayerNode(newNode, for: file)

        let target = min(max(seconds, 0), max(trackDuration - 0.01, 0))
        let startFrame = AVAudioFramePosition(target * sampleRate)
        schedule(
            file: file,
            on: newNode,
            startFrame: startFrame,
            songID: song.id,
            generation: generation
        )

        currentSong = song
        currentFile = file
        currentSampleRate = sampleRate
        segmentStartFrame = startFrame
        duration = trackDuration
        playbackError = nil
        currentSourceInfo = nil
        currentArtwork = ArtworkStore.shared.cachedArtwork(for: song.fileName)
        currentArtworkSongID = song.id
        nowPlayingArtwork = nil
        clock.update(target)
        activeNode = newNode
        queueCount = queue.count
        currentIndex = queue.firstIndex(where: { $0.id == song.id }) ?? currentIndex
        queuePosition = currentIndex + 1

        if autoplay {
            if activateAudioSession(), startEngineIfNeeded() {
                newNode.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
        } else {
            newNode.volume = 1
            isPlaying = false
        }

        if autoplay, isPlaying {
            let fadeSeconds = settings.fadeOption.seconds
            if fadeSeconds > 0 {
                beginCrossfade(
                    oldNode: oldNode?.isPlaying == true ? oldNode : nil,
                    newNode: newNode,
                    seconds: fadeSeconds
                )
            } else {
                oldNode?.stop()
                oldNode?.volume = 0
                newNode.volume = 1
            }
        } else {
            oldNode?.stop()
            oldNode?.volume = 0
            newNode.volume = 1
        }

        if markPlayed {
            onSongStarted?(song)
        }

        loadArtwork(for: song, url: url, generation: generation)
        loadSourceInformation(for: song, url: url, generation: generation)
        prepareNormalization(for: song, url: url, generation: generation)
        updateNowPlayingInfo()
        updateRemoteCommandAvailability()
    }

    private func configurePlayerNode(_ node: AVAudioPlayerNode, for file: AVAudioFile) {
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: transitionMixer, format: file.processingFormat)
    }

    private func schedule(
        file: AVAudioFile,
        on node: AVAudioPlayerNode,
        startFrame: AVAudioFramePosition,
        songID: UUID,
        generation: Int
    ) {
        let remaining = max(file.length - startFrame, 0)
        let frameCount = AVAudioFrameCount(min(remaining, Int64(UInt32.max)))

        guard frameCount > 0 else { return }

        node.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackCompletion(songID: songID, generation: generation)
            }
        }
    }

    private func handleTrackCompletion(songID: UUID, generation: Int) {
        guard generation == playbackGeneration,
              currentSong?.id == songID,
              isPlaying else {
            return
        }

        advanceAfterTrackEnd()
    }

    private func advanceAfterTrackEnd() {
        guard let song = currentSong, !queue.isEmpty else {
            finishQueue()
            return
        }

        switch settings.playbackMode {
        case .repeatOne:
            startTrack(song, at: 0, autoplay: true, markPlayed: true)
        case .sequence:
            guard currentIndex + 1 < queue.count else {
                finishQueue()
                return
            }
            currentIndex += 1
            queuePosition = currentIndex + 1
            startTrack(queue[currentIndex], at: 0, autoplay: true, markPlayed: true)
        case .repeatAll:
            currentIndex = (currentIndex + 1) % queue.count
            queuePosition = currentIndex + 1
            startTrack(queue[currentIndex], at: 0, autoplay: true, markPlayed: true)
        case .shuffle:
            currentIndex = queue.count > 1
                ? randomIndex(excluding: currentIndex)
                : currentIndex
            queuePosition = currentIndex + 1
            startTrack(queue[currentIndex], at: 0, autoplay: true, markPlayed: true)
        }
    }

    private func finishQueue() {
        cancelFades()
        playerA.stop()
        playerB.stop()
        playerA.volume = 0
        playerB.volume = 0
        activeNode = nil
        isPlaying = false
        clock.update(duration)
        engine.pause()
        deactivateAudioSession()
        updateNowPlayingInfo()
    }

    private func randomIndex(excluding index: Int) -> Int {
        guard queue.count > 1 else { return 0 }
        var candidate = Int.random(in: 0..<queue.count)
        while candidate == index {
            candidate = Int.random(in: 0..<queue.count)
        }
        return candidate
    }

    private func beginCrossfade(
        oldNode: AVAudioPlayerNode?,
        newNode: AVAudioPlayerNode,
        seconds: Double
    ) {
        let duration = max(seconds, 0.08)
        let oldStartVolume = oldNode?.volume ?? 0
        let steps = max(Int(duration * 24), 8)

        let task = Task { @MainActor [weak self, weak oldNode, weak newNode] in
            for step in 1...steps {
                guard !Task.isCancelled else { return }

                let progress = Float(step) / Float(steps)
                let eased = 1 - pow(1 - progress, 2)
                newNode?.volume = eased
                oldNode?.volume = oldStartVolume * (1 - eased)
                try? await Task.sleep(
                    nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000)
                )
            }

            guard !Task.isCancelled else { return }
            newNode?.volume = 1
            oldNode?.stop()
            oldNode?.volume = 0
            _ = self
        }

        fadeTasks.append(task)
    }

    private func cancelFades() {
        for task in fadeTasks {
            task.cancel()
        }
        fadeTasks.removeAll()
    }

    private func loadArtwork(for song: Song, url: URL, generation: Int) {
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await ArtworkStore.shared.artwork(for: song, url: url)

            guard !Task.isCancelled,
                  generation == playbackGeneration,
                  currentSong?.id == song.id else {
                return
            }

            currentArtwork = image
            currentArtworkSongID = song.id
            if let image {
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                nowPlayingArtwork = nil
            }
            updateNowPlayingInfo()
        }
    }

    private func loadSourceInformation(for song: Song, url: URL, generation: Int) {
        informationTask?.cancel()
        informationTask = Task { @MainActor [weak self] in
            let information = await AudioSourceInfoReader.read(from: url)

            guard let self,
                  !Task.isCancelled,
                  generation == playbackGeneration,
                  currentSong?.id == song.id else {
                return
            }

            currentSourceInfo = information
        }
    }

    private func prepareNormalization(for song: Song, url: URL, generation: Int) {
        normalizationTask?.cancel()

        guard settings.normalizationEnabled else {
            applyNormalizationGain(0, animated: false)
            return
        }

        applyNormalizationGain(0, animated: false)

        if let cached = normalizationCache[song.fileName] {
            applyNormalizationGain(cached, animated: true)
            return
        }

        normalizationTask = Task { @MainActor [weak self] in
            let gain = await LoudnessAnalyzer.gainDB(for: url)

            guard let self,
                  !Task.isCancelled,
                  generation == playbackGeneration,
                  currentSong?.id == song.id else {
                return
            }

            guard let gain else { return }
            normalizationCache[song.fileName] = gain
            applyNormalizationGain(gain, animated: true)
        }
    }

    private func applyNormalizationSetting() {
        normalizationRampTask?.cancel()
        normalizationTask?.cancel()

        guard settings.normalizationEnabled else {
            applyNormalizationGain(0, animated: true)
            return
        }

        guard let song = currentSong,
              let urlProvider = currentURLProvider else {
            return
        }

        if let cached = normalizationCache[song.fileName] {
            applyNormalizationGain(cached, animated: true)
            return
        }

        let generation = playbackGeneration
        let url = urlProvider(song)
        normalizationTask = Task { @MainActor [weak self] in
            let gain = await LoudnessAnalyzer.gainDB(for: url)

            guard let self,
                  !Task.isCancelled,
                  generation == playbackGeneration,
                  currentSong?.id == song.id else {
                return
            }

            guard let gain else { return }
            normalizationCache[song.fileName] = gain
            applyNormalizationGain(gain, animated: true)
        }
    }

    private func applyNormalizationGain(_ gainDB: Float, animated: Bool) {
        currentNormalizationGainDB = gainDB
        normalizationRampTask?.cancel()

        guard animated else {
            normalizationNode.globalGain = gainDB
            return
        }

        let start = normalizationNode.globalGain
        normalizationRampTask = Task { @MainActor [weak self] in
            let steps = 10
            for step in 1...steps {
                guard !Task.isCancelled else { return }

                let progress = Float(step) / Float(steps)
                self?.normalizationNode.globalGain = start + (gainDB - start) * progress
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    private func configureNormalizationNode() {
        guard let band = normalizationNode.bands.first else { return }
        band.frequency = 1_000
        band.bandwidth = 1
        band.gain = 0
        band.bypass = true
        normalizationNode.bypass = false
        normalizationNode.globalGain = 0
    }

    private func configureEngine() {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 2
        ) else {
            return
        }

        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(transitionMixer)
        engine.attach(equalizer.node)
        engine.attach(normalizationNode)
        engine.attach(timePitchNode)

        engine.connect(transitionMixer, to: equalizer.node, format: format)
        engine.connect(equalizer.node, to: normalizationNode, format: format)
        engine.connect(normalizationNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)

        timePitchNode.pitch = 0
        timePitchNode.overlap = 8
        timePitchNode.rate = settings.playbackRateValue
        engine.mainMixerNode.outputVolume = Float(settings.appVolume)
        engineConfigured = true
    }

    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        guard engineConfigured else {
            playbackError = "音频引擎未完成配置。"
            return false
        }

        do {
            if !engine.isRunning {
                try engine.start()
            }
            return true
        } catch {
            playbackError = "无法启动音频引擎：\(error.localizedDescription)"
            return false
        }
    }

    private func bindPlaybackClock() {
        $isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateClockSubscription()
                }
            }
            .store(in: &cancellables)
    }

    private func updateClockSubscription() {
        let shouldRun = appIsActive && isPlaying

        if shouldRun {
            guard clockCancellable == nil else { return }

            clockCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.syncClockFromPlayer()
                    }
                }
        } else {
            clockCancellable?.cancel()
            clockCancellable = nil
        }
    }

    private func syncClockFromPlayer() {
        guard isPlaying,
              let node = activeNode,
              node.isPlaying,
              let renderTime = node.lastRenderTime,
              renderTime.isSampleTimeValid,
              let playerTime = node.playerTime(forNodeTime: renderTime),
              playerTime.sampleRate > 0 else {
            return
        }

        let elapsedWithinSegment = Double(playerTime.sampleTime) / playerTime.sampleRate
        let elapsed = Double(segmentStartFrame) / currentSampleRate + elapsedWithinSegment
        clock.update(min(max(elapsed, 0), max(duration, 0)))
    }

    private func bindSettings() {
        Publishers.CombineLatest3(
            settings.$equalizerEnabled,
            settings.$equalizerPreset,
            settings.$customEqualizerGains
        )
        .dropFirst()
        .debounce(for: .milliseconds(45), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _ in
            Task { @MainActor [weak self] in
                self?.applyEqualizerSettings(animated: true)
            }
        }
        .store(in: &cancellables)

        settings.$normalizationEnabled
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applyNormalizationSetting()
                }
            }
            .store(in: &cancellables)

        settings.$playbackRate
            .dropFirst()
            .sink { [weak self] rate in
                Task { @MainActor [weak self] in
                    self?.timePitchNode.rate = Float(rate.rawValue)
                    self?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)

        settings.$appVolume
            .dropFirst()
            .sink { [weak self] volume in
                Task { @MainActor [weak self] in
                    self?.engine.mainMixerNode.outputVolume = Float(volume)
                }
            }
            .store(in: &cancellables)

        settings.$playbackMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateRemoteCommandAvailability()
                }
            }
            .store(in: &cancellables)
    }

    private func applyEqualizerSettings(animated: Bool) {
        equalizer.apply(
            gains: settings.effectiveEqualizerGains,
            enabled: settings.equalizerEnabled,
            animated: animated
        )
    }

    @discardableResult
    private func configureAudioSessionIfNeeded() -> Bool {
        if audioSessionConfigured {
            return true
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
        } catch {
            do {
                try session.setCategory(.playback, options: [])
            } catch {
                playbackError = audioSessionFailure(stage: "分类配置", error: error)
                return false
            }
        }

        do {
            try session.setMode(.default)
        } catch {
            playbackError = audioSessionFailure(stage: "模式配置", error: error)
            return false
        }

        audioSessionConfigured = true
        return true
    }

    @discardableResult
    private func activateAudioSession() -> Bool {
        guard configureAudioSessionIfNeeded() else {
            return false
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            return true
        } catch {
            playbackError = audioSessionFailure(stage: "激活", error: error)
            return false
        }
    }

    private func audioSessionFailure(stage: String, error: Error) -> String {
        let error = error as NSError
        if error.domain == NSOSStatusErrorDomain {
            return "音频会话\(stage)失败：\(error.localizedDescription)（OSStatus \(error.code)）"
        }
        return "音频会话\(stage)失败：\(error.localizedDescription)"
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default

        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleInterruption(notification)
                }
            }
        )

        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleRouteChange(notification)
                }
            }
        )

        audioSessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rebuildAudioEngine()
                }
            }
        )
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default

        audioSessionObservers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.appIsActive = true
                    self.syncClockFromPlayer()
                    self.updateNowPlayingInfo()
                    self.updateClockSubscription()
                }
            }
        )

        audioSessionObservers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.syncClockFromPlayer()
                    self.appIsActive = false
                    self.updateNowPlayingInfo()
                    self.updateClockSubscription()
                }
            }
        )
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

        switch reason {
        case .oldDeviceUnavailable:
            if isPlaying {
                shouldResumeAfterRouteChange = true
                pause()
            }
        case .newDeviceAvailable:
            if shouldResumeAfterRouteChange, currentSong != nil, !isPlaying {
                shouldResumeAfterRouteChange = false
                resume()
            }
        default:
            break
        }
    }

    private func rebuildAudioEngine() {
        let savedSong = currentSong
        let savedTime = clock.time
        let savedPlaying = isPlaying
        let savedProvider = currentURLProvider
        let savedQueue = queue
        let savedIndex = currentIndex

        playbackGeneration &+= 1
        cancelFades()
        playerA.stop()
        playerB.stop()
        engine.stop()

        if engineConfigured {
            for node in [
                playerA,
                playerB,
                transitionMixer,
                equalizer.node,
                normalizationNode,
                timePitchNode
            ] {
                engine.detach(node)
            }
        }

        engine = AVAudioEngine()
        engineConfigured = false
        audioSessionConfigured = false
        configureEngine()
        configureNormalizationNode()
        configureRemoteCommands()
        applyEqualizerSettings(animated: false)

        currentURLProvider = savedProvider
        queue = savedQueue
        queueCount = savedQueue.count
        currentIndex = savedIndex

        if let savedSong, savedProvider != nil, !savedQueue.isEmpty {
            startTrack(
                savedSong,
                at: savedTime,
                autoplay: savedPlaying,
                markPlayed: false
            )
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
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(clock.time, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying
                ? settings.playbackRate.rawValue
                : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if queueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
        }

        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }
}
