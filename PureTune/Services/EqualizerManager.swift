import AVFoundation
import Foundation

@MainActor
final class EqualizerManager {
    let node: AVAudioUnitEQ

    private var currentGains: [Float]
    private var rampTask: Task<Void, Never>?

    init() {
        node = AVAudioUnitEQ(numberOfBands: SettingsManager.frequencies.count)
        currentGains = Array(repeating: 0, count: SettingsManager.frequencies.count)

        for (index, frequency) in SettingsManager.frequencies.enumerated() {
            guard let band = node.bands[safe: index] else { continue }

            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false

            if index == 0 {
                band.filterType = .lowShelf
                band.bandwidth = 0.7
            } else if index == SettingsManager.frequencies.count - 1 {
                band.filterType = .highShelf
                band.bandwidth = 0.7
            } else {
                band.filterType = .parametric
            }
        }

        node.globalGain = 0
        node.bypass = true
    }

    func apply(gains: [Float], enabled: Bool, animated: Bool) {
        let target = normalized(gains)
        rampTask?.cancel()

        guard animated else {
            applyImmediately(target, enabled: enabled)
            return
        }

        if enabled {
            node.bypass = false
        }

        let start = currentGains
        rampTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let steps = 12
            for step in 1...steps {
                guard !Task.isCancelled else { return }

                let progress = Float(step) / Float(steps)
                let eased = 1 - pow(1 - progress, 3)
                let interpolated = zip(start, target).map { from, to in
                    from + (to - from) * eased
                }
                applyBandValues(interpolated)

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            guard !Task.isCancelled else { return }
            applyBandValues(target)
            if !enabled {
                node.bypass = true
            }
        }
    }

    private func applyImmediately(_ gains: [Float], enabled: Bool) {
        applyBandValues(gains)
        node.bypass = !enabled
    }

    private func applyBandValues(_ gains: [Float]) {
        currentGains = gains

        for (index, gain) in gains.enumerated() {
            node.bands[safe: index]?.gain = gain
        }

        let maximumBoost = gains.max() ?? 0
        node.globalGain = maximumBoost > 0 ? -min(maximumBoost * 0.25, 4) : 0
    }

    private func normalized(_ gains: [Float]) -> [Float] {
        let count = SettingsManager.frequencies.count
        var result = Array(gains.prefix(count))

        if result.count < count {
            result.append(contentsOf: Array(repeating: 0, count: count - result.count))
        }

        return result.map { min(max($0, -12), 12) }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
