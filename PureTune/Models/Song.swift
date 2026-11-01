import Foundation

struct Song: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let fileSize: Int64
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        title: String,
        artist: String = "",
        album: String = "",
        duration: Double = 0,
        fileSize: Int64 = 0,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }

    var displayArtist: String {
        artist.isEmpty ? "未知艺术家" : artist
    }

    var displayAlbum: String {
        album.isEmpty ? "未知专辑" : album
    }

    var durationText: String {
        PlaybackTimeFormatter.string(from: duration)
    }

    var fileSizeText: String {
        guard fileSize > 0 else { return "" }
        return ByteCountFormatter.string(
            fromByteCount: fileSize,
            countStyle: .file
        )
    }

    var fileExtensionText: String {
        let value = (fileName as NSString).pathExtension.uppercased()
        return value.isEmpty ? "AUDIO" : value
    }

    var searchableText: String {
        "\(title) \(artist) \(album)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case title
        case artist
        case album
        case duration
        case fileSize
        case dateAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decode(String.self, forKey: .fileName)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
    }
}

enum PlaybackTimeFormatter {
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainder = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
