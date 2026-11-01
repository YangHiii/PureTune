import AVFoundation
import Combine
import Foundation

struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isImporting = false
    @Published var importAlert: ImportAlert?

    private let fileManager: FileManager
    private let musicDirectory: URL
    private let indexURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storage = documents.appendingPathComponent("PureTune", isDirectory: true)
        musicDirectory = storage.appendingPathComponent("Music", isDirectory: true)
        indexURL = storage.appendingPathComponent("library.json")

        do {
            try fileManager.createDirectory(
                at: musicDirectory,
                withIntermediateDirectories: true
            )
            loadIndex()
        } catch {
            importAlert = ImportAlert(
                title: "无法创建本地音乐库",
                message: error.localizedDescription
            )
        }
    }

    func fileURL(for song: Song) -> URL {
        musicDirectory.appendingPathComponent(song.fileName)
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, !isImporting else { return }

        isImporting = true
        defer { isImporting = false }

        var importedSongs: [Song] = []
        var issues: [String] = []

        for source in urls {
            do {
                importedSongs.append(try await importFile(source))
            } catch {
                issues.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if !importedSongs.isEmpty {
            songs.append(contentsOf: importedSongs)
            sortSongs()
            persistIndex()
        }

        guard !issues.isEmpty else { return }

        let details = issues.prefix(4).joined(separator: "\n")
        if importedSongs.isEmpty {
            importAlert = ImportAlert(
                title: "未能导入音乐",
                message: details
            )
        } else {
            importAlert = ImportAlert(
                title: "部分音乐未导入",
                message: "已成功导入 \(importedSongs.count) 首。\n\(details)"
            )
        }
    }

    @discardableResult
    func delete(_ song: Song) -> Bool {
        let url = fileURL(for: song)

        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                importAlert = ImportAlert(
                    title: "无法删除音乐文件",
                    message: error.localizedDescription
                )
                return false
            }
        }

        songs.removeAll { $0.id == song.id }
        persistIndex()
        return true
    }

    func presentImportError(_ error: Error) {
        importAlert = ImportAlert(
            title: "无法打开文件",
            message: error.localizedDescription
        )
    }

    private func importFile(_ source: URL) async throws -> Song {
        let pathExtension = source.pathExtension.lowercased()
        guard !pathExtension.isEmpty else {
            throw ImportFailure.missingFileExtension
        }

        let fileName = "\(UUID().uuidString).\(pathExtension)"
        let destination = musicDirectory.appendingPathComponent(fileName)
        let didAccess = source.startAccessingSecurityScopedResource()

        defer {
            if didAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: source, to: destination)
            }.value

            return try await readSong(
                at: destination,
                fileName: fileName,
                fallbackTitle: source.deletingPathExtension().lastPathComponent
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func readSong(
        at url: URL,
        fileName: String,
        fallbackTitle: String
    ) async throws -> Song {
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)

        guard isPlayable, duration.isFinite, duration > 0 else {
            throw ImportFailure.notPlayable
        }

        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let title = await stringValue(for: .commonKeyTitle, in: metadata)
        let artist = await stringValue(for: .commonKeyArtist, in: metadata)
        let album = await stringValue(for: .commonKeyAlbumName, in: metadata)

        return Song(
            fileName: fileName,
            title: title ?? fallbackTitle,
            artist: artist ?? "",
            album: album ?? "",
            duration: duration
        )
    }

    private func stringValue(
        for key: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        guard let item = metadata.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.stringValue) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }

        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode([Song].self, from: data)
            let existing = decoded.filter {
                fileManager.fileExists(atPath: fileURL(for: $0).path)
            }

            songs = existing.sorted(by: Self.sort)

            if existing.count != decoded.count {
                persistIndex()
            }
        } catch {
            songs = []
            importAlert = ImportAlert(
                title: "曲库索引读取失败",
                message: "已保留音乐文件，但暂时无法恢复歌曲列表。\n\(error.localizedDescription)"
            )
        }
    }

    private func sortSongs() {
        songs.sort(by: Self.sort)
    }

    private static func sort(_ lhs: Song, _ rhs: Song) -> Bool {
        let comparison = lhs.title.localizedStandardCompare(rhs.title)
        if comparison == .orderedSame {
            return lhs.dateAdded < rhs.dateAdded
        }
        return comparison == .orderedAscending
    }

    private func persistIndex() {
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            importAlert = ImportAlert(
                title: "无法保存本地曲库",
                message: error.localizedDescription
            )
        }
    }
}

private enum ImportFailure: LocalizedError {
    case missingFileExtension
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .missingFileExtension:
            return "文件缺少扩展名，无法识别音频格式。"
        case .notPlayable:
            return "文件无法解码或不是有效的音频文件。"
        }
    }
}
