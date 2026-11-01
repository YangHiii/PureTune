import AudioToolbox
import AVFoundation
import Foundation

enum AudioSourceInfoReader {
    static func read(from url: URL) async -> AudioSourceInfo? {
        await Task.detached(priority: .utility) {
            readSynchronously(from: url)
        }.value
    }

    nonisolated private static func readSynchronously(from url: URL) -> AudioSourceInfo? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.fileFormat
        let description = format.streamDescription.pointee
        let sampleRate = description.mSampleRate
        let channelCount = Int(description.mChannelsPerFrame)
        let bitDepth = description.mBitsPerChannel > 0
            ? Int(description.mBitsPerChannel)
            : nil
        let formatID = description.mFormatID
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .flatMap { $0 }
            .map(Int64.init) ?? 0
        let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

        let fileExtension = url.pathExtension.uppercased()
        let codec = codecName(for: formatID)

        return AudioSourceInfo(
            fileFormat: fileExtension.isEmpty ? (codec ?? "AUDIO") : fileExtension,
            codec: codec,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: channelCount,
            fileSize: fileSize,
            duration: duration,
            isLossless: isLossless(formatID)
        )
    }

    nonisolated private static func isLossless(_ formatID: AudioFormatID) -> Bool? {
        switch formatID {
        case kAudioFormatLinearPCM,
             kAudioFormatAppleLossless,
             kAudioFormatFLAC:
            return true
        case kAudioFormatMPEGLayer3,
             kAudioFormatMPEG4AAC,
             kAudioFormatMPEG4AAC_HE,
             kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatOpus:
            return false
        default:
            return nil
        }
    }

    nonisolated private static func codecName(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatLinearPCM:
            return "PCM"
        case kAudioFormatAppleLossless:
            return "ALAC"
        case kAudioFormatFLAC:
            return "FLAC"
        case kAudioFormatMPEGLayer3:
            return "MP3"
        case kAudioFormatMPEG4AAC:
            return "AAC"
        case kAudioFormatMPEG4AAC_HE:
            return "HE-AAC"
        case kAudioFormatMPEG4AAC_HE_V2:
            return "HE-AAC v2"
        case kAudioFormatOpus:
            return "Opus"
        default:
            return nil
        }
    }
}

enum LoudnessAnalyzer {
    static func gainDB(for url: URL, targetRMSDB: Float = -18) async -> Float? {
        await Task.detached(priority: .utility) {
            analyzeGainDB(from: url, targetRMSDB: targetRMSDB)
        }.value
    }

    nonisolated private static func analyzeGainDB(
        from url: URL,
        targetRMSDB: Float
    ) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              format.channelCount > 0,
              format.sampleRate > 0 else {
            return nil
        }

        let totalFrames = file.length
        guard totalFrames > 0 else { return nil }

        let windowLength = AVAudioFramePosition(
            min(Double(totalFrames), format.sampleRate * 6)
        )
        guard windowLength > 0 else { return nil }

        let fractionStarts: [Double] = [0.04, 0.28, 0.52, 0.76]
        var squareSum = 0.0
        var sampleCount = 0.0
        var peak = 0.0

        for fraction in fractionStarts {
            if Task.isCancelled { return nil }

            let start = min(
                AVAudioFramePosition(Double(totalFrames) * fraction),
                max(totalFrames - windowLength, 0)
            )
            let remaining = totalFrames - start
            let framesToRead = AVAudioFrameCount(min(windowLength, remaining))
            guard framesToRead > 0 else { continue }

            file.framePosition = start
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRead
            ) else {
                continue
            }

            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                continue
            }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channels = buffer.floatChannelData else {
                continue
            }

            for channelIndex in 0..<Int(format.channelCount) {
                let samples = channels[channelIndex]
                for index in 0..<frameLength {
                    let value = Double(samples[index])
                    squareSum += value * value
                    peak = max(peak, abs(value))
                }
                sampleCount += Double(frameLength)
            }
        }

        guard sampleCount > 0, squareSum > 0, peak > 0 else { return nil }

        let rms = sqrt(squareSum / sampleCount)
        guard rms > 0.000_001 else { return nil }

        let measuredDB = Float(20 * log10(rms))
        var gain = targetRMSDB - measuredDB

        let peakHeadroomDB = Float(20 * log10(0.94 / peak))
        gain = min(gain, peakHeadroomDB)
        gain = min(max(gain, -12), 9)

        return (gain * 10).rounded() / 10
    }
}
