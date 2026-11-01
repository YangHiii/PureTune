import Foundation

enum EqualizerPreset: String, CaseIterable, Codable, Identifiable {
    case flat
    case pop
    case rock
    case classical
    case jazz
    case vocal
    case bass
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat:
            return "原声"
        case .pop:
            return "流行"
        case .rock:
            return "摇滚"
        case .classical:
            return "古典"
        case .jazz:
            return "爵士"
        case .vocal:
            return "人声"
        case .bass:
            return "低音增强"
        case .custom:
            return "自定义"
        }
    }

    var gains: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .pop:
            return [0.8, 1.0, 0.6, 0.1, -0.6, -0.5, 0.4, 1.1, 1.4, 1.6]
        case .rock:
            return [2.8, 2.4, 1.4, 0.2, -0.8, -0.4, 0.8, 1.8, 2.4, 2.6]
        case .classical:
            return [0.8, 0.5, 0.2, 0, -0.4, -0.3, 0.2, 0.8, 1.2, 1.4]
        case .jazz:
            return [1.5, 1.2, 0.5, 0.2, -0.4, 0.1, 0.7, 1.2, 1.6, 1.5]
        case .vocal:
            return [-1.4, -1.0, -0.2, 0.8, 2.1, 2.6, 2.2, 1.2, 0, -0.8]
        case .bass:
            return [4.8, 4.0, 3.0, 1.8, 0.5, 0, 0, 0, 0, 0]
        case .custom:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}

enum PlaybackMode: String, CaseIterable, Codable, Identifiable {
    case sequence
    case repeatOne
    case repeatAll
    case shuffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequence:
            return "顺序播放"
        case .repeatOne:
            return "单曲循环"
        case .repeatAll:
            return "列表循环"
        case .shuffle:
            return "随机播放"
        }
    }

    var shortTitle: String {
        switch self {
        case .sequence:
            return "顺序"
        case .repeatOne:
            return "单曲"
        case .repeatAll:
            return "循环"
        case .shuffle:
            return "随机"
        }
    }

    var systemImage: String {
        switch self {
        case .sequence:
            return "arrow.right"
        case .repeatOne:
            return "repeat.1"
        case .repeatAll:
            return "repeat"
        case .shuffle:
            return "shuffle"
        }
    }

    var next: PlaybackMode {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .repeatAll }
        return all[(index + 1) % all.count]
    }
}

enum FadeOption: Int, CaseIterable, Codable, Identifiable {
    case off = 0
    case oneSecond = 1
    case twoSeconds = 2
    case threeSeconds = 3

    var id: Int { rawValue }

    var seconds: Double {
        Double(rawValue)
    }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .oneSecond:
            return "1 秒"
        case .twoSeconds:
            return "2 秒"
        case .threeSeconds:
            return "3 秒"
        }
    }
}

enum PlaybackRateOption: Double, CaseIterable, Codable, Identifiable {
    case x075 = 0.75
    case x100 = 1.0
    case x125 = 1.25
    case x150 = 1.5
    case x200 = 2.0

    var id: Double { rawValue }

    var title: String {
        String(format: "%.2gx", rawValue)
    }
}

struct AudioSourceInfo: Equatable, Sendable {
    let fileFormat: String
    let codec: String?
    let sampleRate: Double
    let bitDepth: Int?
    let channelCount: Int
    let fileSize: Int64
    let duration: Double
    let isLossless: Bool?

    var sampleRateText: String {
        guard sampleRate > 0 else { return "未知" }
        if sampleRate >= 1_000 {
            let value = sampleRate / 1_000
            return value.rounded() == value
                ? String(format: "%.0f kHz", value)
                : String(format: "%.1f kHz", value)
        }
        return String(format: "%.0f Hz", sampleRate)
    }

    var bitDepthText: String? {
        guard let bitDepth, bitDepth > 0 else { return nil }
        return "\(bitDepth) bit"
    }

    var channelText: String {
        switch channelCount {
        case 1:
            return "单声道"
        case 2:
            return "立体声"
        default:
            return "\(channelCount) 声道"
        }
    }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var durationText: String {
        PlaybackTimeFormatter.string(from: duration)
    }

    var losslessText: String? {
        guard let isLossless else { return nil }
        return isLossless ? "无损编码" : "有损编码"
    }
}
