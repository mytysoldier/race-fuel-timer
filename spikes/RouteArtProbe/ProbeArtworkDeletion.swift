import Foundation

// Simulator試作用。指定フォルダ直下のPNG以外を削除しない。
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
