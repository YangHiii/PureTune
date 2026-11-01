import Combine
import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    @Published var equalizerEnabled: Bool {
        didSet { scheduleSave() }
    }

    @Published var equalizerPreset: EqualizerPreset {
        didSet { scheduleSave() }
    }

    @Published var customEqualizerGains: [Float] {
        didSet { scheduleSave() }
    }

    @Published var normalizationEnabled: Bool {
        didSet { scheduleSave() }
    }

    @Published var fadeOption: FadeOption {
        didSet { scheduleSave() }
    }

    @Published var playbackRate: PlaybackRateOption {
        didSet { scheduleSave() }
    }

    @Published var appVolume: Double {
        didSet { scheduleSave() }
    }

    @Published var playbackMode: PlaybackMode {
        didSet { scheduleSave() }
    }

    static let frequencies: [Float] = [
        31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    private let defaults: UserDefaults
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedGains = defaults.array(forKey: Keys.customGains) as? [Double]
        let gainedValues = storedGains?.prefix(Self.frequencies.count).map(Float.init)
            ?? []

        let normalizedGains: [Float]
        if gainedValues.count == Self.frequencies.count {
            normalizedGains = Array(gainedValues)
        } else {
            normalizedGains = Array(repeating: 0, count: Self.frequencies.count)
        }

        equalizerEnabled = defaults.object(forKey: Keys.equalizerEnabled) as? Bool ?? false
        equalizerPreset = EqualizerPreset(
            rawValue: defaults.string(forKey: Keys.equalizerPreset) ?? ""
        ) ?? .flat
        customEqualizerGains = normalizedGains
        normalizationEnabled = defaults.object(forKey: Keys.normalizationEnabled) as? Bool ?? false
        fadeOption = FadeOption(
            rawValue: defaults.object(forKey: Keys.fadeOption) as? Int ?? FadeOption.oneSecond.rawValue
        ) ?? .oneSecond
        playbackRate = PlaybackRateOption(
            rawValue: defaults.object(forKey: Keys.playbackRate) as? Double ?? 1.0
        ) ?? .x100
        appVolume = min(max(defaults.object(forKey: Keys.appVolume) as? Double ?? 1.0, 0), 1)
        playbackMode = PlaybackMode(
            rawValue: defaults.string(forKey: Keys.playbackMode) ?? ""
        ) ?? .repeatAll

        isLoading = false

        saveSubject
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.persist()
            }
            .store(in: &cancellables)
    }

    var effectiveEqualizerGains: [Float] {
        if equalizerPreset == .custom {
            return customEqualizerGains
        }
        return equalizerPreset.gains
    }

    var playbackRateValue: Float {
        Float(playbackRate.rawValue)
    }

    func selectPreset(_ preset: EqualizerPreset) {
        equalizerPreset = preset
    }

    func setBandGain(index: Int, value: Float) {
        guard Self.frequencies.indices.contains(index) else { return }

        var gains = effectiveEqualizerGains
        gains[index] = min(max(value, -12), 12)
        customEqualizerGains = gains
        equalizerPreset = .custom
    }

    func resetEqualizer() {
        equalizerPreset = .flat
        customEqualizerGains = Array(repeating: 0, count: Self.frequencies.count)
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
    }

    func resetAudioEffects() {
        equalizerEnabled = false
        equalizerPreset = .flat
        customEqualizerGains = Array(repeating: 0, count: Self.frequencies.count)
        normalizationEnabled = false
        fadeOption = .oneSecond
        playbackRate = .x100
        appVolume = 1.0
        persist()
    }

    func resetToDefaults() {
        equalizerEnabled = false
        equalizerPreset = .flat
        customEqualizerGains = Array(repeating: 0, count: Self.frequencies.count)
        normalizationEnabled = false
        fadeOption = .oneSecond
        playbackRate = .x100
        appVolume = 1.0
        playbackMode = .repeatAll
        persist()
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveSubject.send(())
    }

    private func persist() {
        defaults.set(equalizerEnabled, forKey: Keys.equalizerEnabled)
        defaults.set(equalizerPreset.rawValue, forKey: Keys.equalizerPreset)
        defaults.set(customEqualizerGains.map(Double.init), forKey: Keys.customGains)
        defaults.set(normalizationEnabled, forKey: Keys.normalizationEnabled)
        defaults.set(fadeOption.rawValue, forKey: Keys.fadeOption)
        defaults.set(playbackRate.rawValue, forKey: Keys.playbackRate)
        defaults.set(appVolume, forKey: Keys.appVolume)
        defaults.set(playbackMode.rawValue, forKey: Keys.playbackMode)
    }

    private enum Keys {
        static let equalizerEnabled = "PureTune.eq.enabled"
        static let equalizerPreset = "PureTune.eq.preset"
        static let customGains = "PureTune.eq.customGains"
        static let normalizationEnabled = "PureTune.normalization"
        static let fadeOption = "PureTune.fadeSeconds"
        static let playbackRate = "PureTune.playbackRate"
        static let appVolume = "PureTune.appVolume"
        static let playbackMode = "PureTune.playbackMode"
    }
}
