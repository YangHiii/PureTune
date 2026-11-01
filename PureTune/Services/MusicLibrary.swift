import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ImportProgress: Equatable {
    let completed: Int
    let total: Int
    let fileName: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var statusText: String {
        "正在处理 \(completed) / \(total)"
    }
}

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: ImportProgress?
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
        guard !isImporting else { return }
        guard !urls.isEmpty else {
            reportEmptySelection()
            return
        }

        isImporting = true
        defer {
            isImporting = false
            importProgress = nil
        }

        var importedSongs: [Song] = []
        var issues: [String] = []

        for (index, source) in urls.enumerated() {
            importProgress = ImportProgress(
                completed: index + 1,
                total: urls.count,
                fileName: source.lastPathComponent
            )

            do {
                importedSongs.append(try await importFile(source))
            } catch {
                issues.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if !importedSongs.isEmpty {
            songs.append(contentsOf: importedSongs)
            sortSongs()
            do {
                try persistIndex()
            } catch {
                issues.append("曲库索引保存失败：\(error.localizedDescription)")
            }
        }

        if issues.isEmpty {
            importAlert = ImportAlert(
                title: "导入完成",
                message: "已成功导入 \(importedSongs.count) 首歌曲。"
            )
            return
        }

        let details = issues.prefix(5).joined(separator: "\n")
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
        do {
            try persistIndex()
        } catch {
            importAlert = ImportAlert(
                title: "歌曲已删除，但索引保存失败",
                message: error.localizedDescription
            )
        }
        return true
    }

    func presentImportError(_ error: Error) {
        importAlert = ImportAlert(
            title: "无法打开文件",
            message: error.localizedDescription
        )
    }

    func reportEmptySelection() {
        importAlert = ImportAlert(
            title: "没有收到文件",
            message: "文件选择器没有返回可读取的文件。请重新打开「文件」App，确认歌曲已下载到本机后再试。"
        )
    }

    private func importFile(_ source: URL) async throws -> Song {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? source.resourceValues(forKeys: [
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey
        ])

        if values?.isRegularFile == false {
            throw ImportFailure.notAFile
        }

        if let size = values?.fileSize, size <= 0 {
            throw ImportFailure.emptyFile
        }

        var pathExtension = source.pathExtension.lowercased()
        if pathExtension.isEmpty,
           let preferred = values?.contentType?.preferredFilenameExtension {
            pathExtension = preferred.lowercased()
        }

        guard !pathExtension.isEmpty else {
            throw ImportFailure.missingFileExtension
        }

        let fileName = "\(UUID().uuidString).\(pathExtension)"
        let destination = musicDirectory.appendingPathComponent(fileName)

        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.copyIntoLibrary(from: source, to: destination)
            }.value

            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 else {
                throw ImportFailure.emptyFile
            }

            return try await readSong(
                at: destination,
                fileName: fileName,
                fileSize: Int64(size),
                fallbackTitle: source.deletingPathExtension().lastPathComponent
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    nonisolated private static func copyIntoLibrary(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let sourceSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize

        if let sourceSize, sourceSize <= 0 {
            throw ImportFailure.emptyFile
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
            let copiedSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard copiedSize > 0 else {
                throw ImportFailure.emptyFile
            }
            return
        } catch let directError as ImportFailure {
            throw directError
        } catch {
            try? fileManager.removeItem(at: destination)
        }

        var coordinationError: NSError?
        var copyError: Error?

        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw ImportFailure.readFailed(coordinationError.localizedDescription)
        }
        if let copyError {
            throw ImportFailure.copyFailed(copyError.localizedDescription)
        }

        let copiedSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard copiedSize > 0 else {
            throw ImportFailure.emptyFile
        }
    }

    private func readSong(
        at url: URL,
        fileName: String,
        fileSize: Int64,
        fallbackTitle: String
    ) async throws -> Song {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw ImportFailure.notPlayable
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw ImportFailure.notAudio
            }

            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration.isFinite, duration > 0 else {
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
                duration: duration,
                fileSize: fileSize
            )
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw ImportFailure.notPlayable
        }
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
                try? persistIndex()
            }
        } catch {
            songs = []
            importAlert = ImportAlert(
                title: "曲库索引读取失败",
                message: "音乐文件仍保留在本机，但暂时无法恢复歌曲列表。\n\(error.localizedDescription)"
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

    private func persistIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(songs)
        try data.write(to: indexURL, options: .atomic)
    }
}

private enum ImportFailure: LocalizedError {
    case notAFile
    case missingFileExtension
    case emptyFile
    case readFailed(String)
    case copyFailed(String)
    case notAudio
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "所选项目不是可导入的文件。"
        case .missingFileExtension:
            return "文件缺少扩展名，系统无法识别音频格式。"
        case .emptyFile:
            return "文件内容为空，无法导入。"
        case .readFailed(let detail):
            return "无法读取文件：\(detail)"
        case .copyFailed(let detail):
            return "无法复制到本地音乐库：\(detail)"
        case .notAudio:
            return "文件中没有可播放的音轨。"
        case .notPlayable:
            return "文件无法解码，或不是有效的音频文件。"
        }
    }
}
