import Foundation
import ImageIO

enum ProbeArtworkLibrary {
    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    static func images(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "png" }
        let entries = urls.map { url in
            (url: url, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        return entries.sorted {
            $0.date == $1.date ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.date > $1.date
        }.map(\.url)
    }

    static func thumbnail(at url: URL, maxPixelSize: Int = 900) -> CGImage? {
        guard maxPixelSize > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// 指定フォルダ直下のPNG以外を削除しない。
enum ProbeArtworkDeletion {
    enum DeletionError: Error { case invalidTarget }

    static func remove(_ target: URL, in directory: URL) throws {
        let target = target.standardizedFileURL
        let directory = directory.standardizedFileURL
        guard target.isFileURL, directory.isFileURL,
              target.deletingLastPathComponent() == directory,
              target.pathExtension.lowercased() == "png" else {
            throw DeletionError.invalidTarget
        }
        try FileManager.default.removeItem(at: target)
    }
}
