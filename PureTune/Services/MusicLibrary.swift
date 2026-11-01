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
        guard total > 0 else { return "正在准备文件" }
        if completed >= total {
            return "正在完成 \(total) / \(total)"
        }
        return "正在导入第 \(completed + 1) / \(total) 首"
    }
}

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var recentlyPlayedIDs: [UUID] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isImportCancelling = false
    @Published private(set) var importProgress: ImportProgress?
    @Published var importAlert: ImportAlert?

    private let fileManager: FileManager
    private let musicDirectory: URL
    private let indexURL: URL
    private let historyURL: URL
    private var importCancellationRequested = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storage = documents.appendingPathComponent("PureTune", isDirectory: true)
        musicDirectory = storage.appendingPathComponent("Music", isDirectory: true)
        indexURL = storage.appendingPathComponent("library.json")
        historyURL = storage.appendingPathComponent("history.json")

        do {
            try fileManager.createDirectory(
                at: musicDirectory,
                withIntermediateDirectories: true
            )
            loadIndex()
            loadHistory()
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

    var recentlyPlayedSongs: [Song] {
        let lookup = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        return recentlyPlayedIDs.compactMap { lookup[$0] }
    }

    var totalFileSize: Int64 {
        songs.reduce(0) { $0 + $1.fileSize }
    }

    func markPlayed(_ song: Song) {
        recentlyPlayedIDs.removeAll { $0 == song.id }
        recentlyPlayedIDs.insert(song.id, at: 0)
        if recentlyPlayedIDs.count > 60 {
            recentlyPlayedIDs.removeLast(recentlyPlayedIDs.count - 60)
        }
        persistHistory()
    }

    func importFiles(_ urls: [URL]) async {
        guard !isImporting else { return }
        guard !urls.isEmpty else {
            reportEmptySelection()
            return
        }

        isImporting = true
        isImportCancelling = false
        importCancellationRequested = false
        defer {
            isImporting = false
            isImportCancelling = false
            importCancellationRequested = false
            importProgress = nil
        }

        var importedSongs: [Song] = []
        var skippedCount = 0
        var issues: [String] = []

        for (index, source) in urls.enumerated() {
            if importCancellationRequested {
                break
            }

            importProgress = ImportProgress(
                completed: index,
                total: urls.count,
                fileName: source.lastPathComponent
            )

            do {
                let imported = try await importFile(source)
                if isDuplicate(imported, in: songs) || isDuplicate(imported, in: importedSongs) {
                    try? fileManager.removeItem(at: fileURL(for: imported))
                    skippedCount += 1
                } else {
                    importedSongs.append(imported)
                }
            } catch {
                issues.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }

            importProgress = ImportProgress(
                completed: index + 1,
                total: urls.count,
                fileName: source.lastPathComponent
            )
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

        if importCancellationRequested {
            let importedText = importedSongs.isEmpty
                ? "本次没有保存新歌曲。"
                : "已保存 \(importedSongs.count) 首歌曲。"
            importAlert = ImportAlert(
                title: "导入已取消",
                message: "\(importedText)未处理的文件已停止导入。"
            )
            return
        }

        if issues.isEmpty && skippedCount == 0 {
            importAlert = ImportAlert(
                title: "导入完成",
                message: "已成功导入 \(importedSongs.count) 首歌曲。"
            )
            return
        }

        let details = issues.prefix(5).joined(separator: "\n")
        if importedSongs.isEmpty, skippedCount > 0, issues.isEmpty {
            importAlert = ImportAlert(
                title: "没有新增歌曲",
                message: "这 \(skippedCount) 首歌曲已经在曲库中，无需重复导入。"
            )
        } else if importedSongs.isEmpty {
            importAlert = ImportAlert(
                title: "未能导入音乐",
                message: details.isEmpty
                    ? "所选文件没有产生可保存的歌曲。"
                    : details
            )
        } else {
            let skippedText = skippedCount > 0 ? "\n已跳过 \(skippedCount) 首重复歌曲。" : ""
            let issueText = details.isEmpty ? "" : "\n\(details)"
            importAlert = ImportAlert(
                title: "部分音乐未导入",
                message: "已成功导入 \(importedSongs.count) 首。\(skippedText)\(issueText)"
            )
        }
    }

    func cancelImport() {
        guard isImporting else { return }
        isImportCancelling = true
        importCancellationRequested = true
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
        recentlyPlayedIDs.removeAll { $0 == song.id }
        persistHistory()

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

    func reconcileLibrary() {
        let originalCount = songs.count
        songs = songs.filter {
            fileManager.fileExists(atPath: fileURL(for: $0).path)
        }

        let validIDs = Set(songs.map(\.id))
        recentlyPlayedIDs = recentlyPlayedIDs.filter { validIDs.contains($0) }

        do {
            try persistIndex()
            persistHistory()

            let removed = originalCount - songs.count
            importAlert = ImportAlert(
                title: removed > 0 ? "曲库检查完成" : "曲库状态正常",
                message: removed > 0
                    ? "已清理 \(removed) 条失效记录，音乐文件本身未被删除。"
                    : "所有歌曲文件均可访问。"
            )
        } catch {
            importAlert = ImportAlert(
                title: "曲库检查未完成",
                message: error.localizedDescription
            )
        }
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

    private func isDuplicate(_ candidate: Song, in collection: [Song]) -> Bool {
        collection.contains { existing in
            existing.title.caseInsensitiveCompare(candidate.title) == .orderedSame
                && existing.displayArtist.caseInsensitiveCompare(candidate.displayArtist) == .orderedSame
                && existing.fileSize == candidate.fileSize
                && abs(existing.duration - candidate.duration) < 0.5
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

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        guard let data = try? Data(contentsOf: historyURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return
        }
        recentlyPlayedIDs = ids
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(recentlyPlayedIDs) else { return }
        try? data.write(to: historyURL, options: .atomic)
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
