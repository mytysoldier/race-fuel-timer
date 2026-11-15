import CoreLocation
import Foundation
import Testing
@testable import RaceFuelTimer

@Test func 開始地点を横切る線は保護後に結ばれない() {
    // Arrange
    let points = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                  CLLocationCoordinate2D(latitude: 0, longitude: 0.003),
                  CLLocationCoordinate2D(latitude: 0, longitude: -0.003),
                  CLLocationCoordinate2D(latitude: 0, longitude: 0.009)]

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [], radius: 200)

    // Assert
    #expect(result.breaks.contains(1))
    #expect(!RoutePrivacyProbe.hasDrawableLine(result.points, breaks: result.breaks))
}

@Test func 作品の削除は対象フォルダ外を拒否する() throws {
    // Arrange
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appendingPathComponent("keep.png")
    try Data("fixture".utf8).write(to: image)

    // Act
    let result = Result { try ProbeArtworkDeletion.remove(image, in: root.appendingPathComponent("artworks")) }

    // Assert
    #expect(throws: ProbeArtworkDeletion.DeletionError.self) { try result.get() }
    #expect(FileManager.default.fileExists(atPath: image.path))
}
