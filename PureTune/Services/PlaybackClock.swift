import Combine

@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var time: Double = 0

    func update(_ value: Double) {
        guard value.isFinite else { return }
        time = max(value, 0)
    }

    func reset() {
        time = 0
    }
}
