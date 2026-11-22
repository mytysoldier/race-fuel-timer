import CoreLocation
import Foundation
import Testing
import UIKit
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

@Test func 作品フォルダの準備は既存画像を残してバックアップ対象外にする() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let image = directory.appendingPathComponent("existing.png")
    try Data("fixture".utf8).write(to: image)

    // Act
    try ProbeArtworkLibrary.prepareDirectory(directory)

    // Assert
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    #expect(try Data(contentsOf: image) == Data("fixture".utf8))
}

private func 位置(_ longitude: Double, 秒: TimeInterval, 精度: Double = 5) -> CLLocation {
    CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: longitude),
               altitude: 0, horizontalAccuracy: 精度, verticalAccuracy: 5,
               timestamp: Date(timeIntervalSince1970: 秒))
}

@Test func 通常の移動は分断せず順序を保持する() {
    // Arrange
    let locations = [位置(0, 秒: 0), 位置(0.0001, 秒: 10), 位置(0.0002, 秒: 20)]

    // Act
    let result = RouteGapProbe.analyze(locations)

    // Assert
    #expect(result.points.map(\.longitude) == [0, 0.0001, 0.0002])
    #expect(result.breakIndices.isEmpty)
}

@Test func 精度が無効な点を除き前後を結ばない() {
    // Arrange
    let locations = [位置(0, 秒: 0), 位置(0.0001, 秒: 10, 精度: -1), 位置(0.0002, 秒: 20)]

    // Act
    let result = RouteGapProbe.analyze(locations)

    // Assert
    #expect(result.points.map(\.longitude) == [0, 0.0002])
    #expect(result.breakIndices == [1])
}

@Test func 同時刻や逆順の点はそれぞれ分断する() {
    // Arrange
    let locations = [位置(0, 秒: 10), 位置(0.0001, 秒: 10), 位置(0.0002, 秒: 9)]

    // Act
    let result = RouteGapProbe.analyze(locations)

    // Assert
    #expect(result.points.count == 3)
    #expect(result.breakIndices == [1, 2])
}

@Test func 短時間の大きな移動を分断する() {
    // Arrange
    let locations = [位置(0, 秒: 0), 位置(0.002, 秒: 10)]

    // Act
    let result = RouteGapProbe.analyze(locations)

    // Assert
    #expect(result.points.count == 2)
    #expect(result.breakIndices == [1])
}

@Test func 長時間の間隔は仮の閾値を超えた場合だけ分断する() {
    // Arrange
    let start = 位置(0, 秒: 0)
    let boundary = 位置(0.0006, 秒: 120)
    let beyond = 位置(0.0006, 秒: 121)

    // Act
    let atBoundary = RouteGapProbe.analyze([start, boundary])
    let afterBoundary = RouteGapProbe.analyze([start, beyond])

    // Assert
    #expect(atBoundary.breakIndices.isEmpty)
    #expect(afterBoundary.breakIndices == [1])
}

@Test func 破損画像だけを削除すると正常画像が残る() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let broken = directory.appendingPathComponent("broken.png")
    let good = directory.appendingPathComponent("good.png")
    let goodData = try #require(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }.pngData())
    try Data("broken".utf8).write(to: broken)
    try goodData.write(to: good)

    // Act
    try ProbeArtworkDeletion.remove(broken, in: directory)

    // Assert
    #expect(!FileManager.default.fileExists(atPath: broken.path))
    #expect(try Data(contentsOf: good) == goodData)
    #expect(ProbeArtworkLibrary.thumbnail(at: good) != nil)
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

@Test func 作品は新しい順に並び破損画像も一覧に残る() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let old = directory.appendingPathComponent("old.png")
    let broken = directory.appendingPathComponent("broken.png")
    let ignored = directory.appendingPathComponent("other.txt")
    for url in [old, broken, ignored] { try Data("fixture".utf8).write(to: url) }
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: broken.path)

    // Act
    let images = try ProbeArtworkLibrary.images(in: directory)

    // Assert
    #expect(images.map(\.lastPathComponent) == ["broken.png", "old.png"])
    #expect(ProbeArtworkLibrary.thumbnail(at: broken) == nil)
}

@Test func 存在しない作品フォルダは空の一覧になる() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    // Act
    let images = try ProbeArtworkLibrary.images(in: directory)

    // Assert
    #expect(images.isEmpty)
}

@Test func 同一座標だけのルートは描画可能な線がない() {
    // Arrange
    let point = CLLocationCoordinate2D(latitude: 35, longitude: 139)
    let points = [point, point, point]

    // Act
    let result = RoutePrivacyProbe.hasDrawableLine(points, breaks: [])

    // Assert
    #expect(!result)
}

@Test func 分断された異なる座標は線として扱わない() {
    // Arrange
    let points = [CLLocationCoordinate2D(latitude: 35, longitude: 139),
                  CLLocationCoordinate2D(latitude: 35, longitude: 139.01)]

    // Act
    let separated = RoutePrivacyProbe.hasDrawableLine(points, breaks: [1])
    let connected = RoutePrivacyProbe.hasDrawableLine(points, breaks: [])

    // Assert
    #expect(!separated)
    #expect(connected)
}

@Test func 日付変更線上の同じ地点は線として扱わない() {
    // Arrange
    let east = CLLocationCoordinate2D(latitude: 35, longitude: 180)
    let west = CLLocationCoordinate2D(latitude: 35, longitude: -180)
    let nearby = CLLocationCoordinate2D(latitude: 35, longitude: -179.999)
    let north = CLLocationCoordinate2D(latitude: 35.001, longitude: -180)

    // Act
    let same = RoutePrivacyProbe.hasDrawableLine([east, west], breaks: [])
    let crossed = RoutePrivacyProbe.hasDrawableLine([east, nearby], breaks: [])
    let differentLatitude = RoutePrivacyProbe.hasDrawableLine([east, north], breaks: [])

    // Assert
    #expect(!same)
    #expect(crossed)
    #expect(differentLatitude)
}

@Test func 無効な中間点の前後は結ばれない() {
    // Arrange
    let points = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                  CLLocationCoordinate2D(latitude: 0, longitude: 0.01),
                  CLLocationCoordinate2D(latitude: 100, longitude: 0),
                  CLLocationCoordinate2D(latitude: 0, longitude: -0.01),
                  CLLocationCoordinate2D(latitude: 0, longitude: 0.03)]

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [], radius: 200)

    // Assert
    #expect(result.points.count == 2)
    #expect(result.breaks == [1])
}

@Test func 保護範囲への再侵入後は線を再接続しない() {
    // Arrange
    let points = [0.0, 0.003, 0.004, 0.001, 0.004, 0.005, 0.01].map {
        CLLocationCoordinate2D(latitude: 0, longitude: $0)
    }

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [], radius: 200)

    // Assert
    #expect(result.points.map(\.longitude) == [0.003, 0.004, 0.004, 0.005])
    #expect(result.breaks == [2])
}

@Test func 架空の複数区間で保護後の線は元の隣接点だけを結ぶ() {
    // Arrange
    var seed: UInt64 = 0x105
    func nextOffset() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return Double((seed >> 32) % 10_001) / 1_000_000 - 0.005
    }
    var connectedLines = 0
    var separatedLines = 0

    // Act
    for _ in 0..<40 {
        let points = (0..<40).map { index in
            CLLocationCoordinate2D(latitude: nextOffset() + Double(index) * 0.0000001,
                                   longitude: nextOffset())
        }
        let originalBreaks: Set<Int> = [10, 20, 30]
        let centerIndices = [0, 9, 10, 19, 20, 29, 30, 39]
        for centers in [RoutePrivacyProbe.Centers.overall, .eachSegment] {
            let result = RoutePrivacyProbe.mask(points, breaks: originalBreaks, radius: 200, centers: centers)
            let protectedIndices = centers == .overall ? [0, 39] : centerIndices
            let protected = protectedIndices.map { CLLocation(latitude: points[$0].latitude, longitude: points[$0].longitude) }
            let sourceIndices = result.points.map { point in
                points.firstIndex { $0.latitude == point.latitude && $0.longitude == point.longitude }
            }
            // Assert
            #expect(sourceIndices.allSatisfy { $0 != nil })
            for point in result.points {
                let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
                #expect(protected.allSatisfy { location.distance(from: $0) > 200 })
            }
            separatedLines += result.breaks.count
            guard result.points.count > 1 else { continue }
            for index in 1..<result.points.count where !result.breaks.contains(index) {
                connectedLines += 1
                guard let previous = sourceIndices[index - 1], let current = sourceIndices[index] else {
                    Issue.record("出力点が元のルートにありません")
                    continue
                }
                #expect(current == previous + 1)
                #expect(!originalBreaks.contains(current))
                let a = result.points[index - 1], b = result.points[index]
                for step in 0...20 {
                    let fraction = Double(step) / 20
                    let sample = CLLocation(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                                            longitude: a.longitude + (b.longitude - a.longitude) * fraction)
                    #expect(protected.allSatisfy { sample.distance(from: $0) > 200 })
                }
            }
        }
    }
    #expect(connectedLines > 0)
    #expect(separatedLines > 0)
}
