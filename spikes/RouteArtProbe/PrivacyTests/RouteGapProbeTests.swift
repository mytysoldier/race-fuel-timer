import CoreLocation
import Foundation
import Testing
@testable import RoutePrivacyProbe

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
