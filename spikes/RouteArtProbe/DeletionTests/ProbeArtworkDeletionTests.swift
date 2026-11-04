import Foundation
import Testing
@testable import ProbeArtworkDeletion

@Test func 破損画像だけを削除すると正常画像が残る() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let broken = directory.appendingPathComponent("broken.png")
    let good = directory.appendingPathComponent("good.png")
    try Data("broken".utf8).write(to: broken)
    try Data("good".utf8).write(to: good)

    // Act
    try ProbeArtworkDeletion.remove(broken, in: directory)

    // Assert
    #expect(!FileManager.default.fileExists(atPath: broken.path))
    #expect(try Data(contentsOf: good) == Data("good".utf8))
}

@Test func 対象フォルダ外の画像は削除できない() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let other = directory.appendingPathComponent("other.png")
    try Data("keep".utf8).write(to: other)

    // Act
    let result = Result { try ProbeArtworkDeletion.remove(other, in: directory.appendingPathComponent("images")) }

    // Assert
    #expect(throws: ProbeArtworkDeletion.DeletionError.self) { try result.get() }
    #expect(FileManager.default.fileExists(atPath: other.path))
}

@Test func 存在しない画像の削除は失敗を返す() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let missing = directory.appendingPathComponent("missing.png")

    // Act
    let result = Result { try ProbeArtworkDeletion.remove(missing, in: directory) }

    // Assert
    #expect(throws: (any Error).self) { try result.get() }
}
