import CoreLocation
import Testing
@testable import RoutePrivacyProbe

@Test func 複数区間の端を隠すと中間の区間端も除外される() {
    // Arrange
    let points = (0...10).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) }
        + (20...30).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) }
    let split = 11
    let boundary = [points[0], points[10], points[11], points[21]]

    // Act
    let overall = RoutePrivacyProbe.mask(points, breaks: [split], radius: 200)
    let segments = RoutePrivacyProbe.mask(points, breaks: [split], radius: 200, centers: .eachSegment)

    // Assert
    #expect(overall.points.contains { $0.longitude == points[10].longitude })
    #expect(segments.points.count < overall.points.count)
    #expect(!segments.points.isEmpty)
    for point in segments.points {
        for center in boundary {
            let actual = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let protected = CLLocation(latitude: center.latitude, longitude: center.longitude)
            #expect(actual.distance(from: protected) > 200)
        }
    }
    #expect(segments.breaks.count == 1)
}

@Test func 短い区間の両端を隠すと表示点は残らない() {
    // Arrange
    let points = (0...2).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.0001) }

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [], radius: 200, centers: .eachSegment)

    // Assert
    #expect(result.points.isEmpty)
    #expect(result.breaks.isEmpty)
}

@Test func 区間端が無効な座標なら描画候補を返さない() {
    // Arrange
    let points = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                  CLLocationCoordinate2D(latitude: 100, longitude: 0),
                  CLLocationCoordinate2D(latitude: 0, longitude: 1)]

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [1], radius: 200, centers: .eachSegment)

    // Assert
    #expect(result.points.isEmpty)
    #expect(result.breaks.isEmpty)
}

@Test func 保護範囲を横切る線は両端が範囲外でも結ばれない() {
    // Arrange
    let points = [0.0, 0.01, -0.01, 0.03].map {
        CLLocationCoordinate2D(latitude: 0, longitude: $0)
    }

    // Act
    let result = RoutePrivacyProbe.mask(points, breaks: [], radius: 200, centers: .eachSegment)

    // Assert
    #expect(result.points.count == 2)
    #expect(result.breaks.contains(1))
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

@Test func 架空データの性能測定は各方式と区間数の結果を返す() {
    // Arrange
    let expectedSegments = [1, 1, 10, 10, 101, 101]

    // Act
    let results = RouteMaskPerformance.run()

    // Assert
    #expect(results.map(\.segmentCount) == expectedSegments)
    #expect(results.map(\.remainingPoints) == [6_014, 6_014, 6_014, 5_690, 6_014, 2_414])
    #expect(results.allSatisfy { $0.medianSeconds.isFinite && $0.medianSeconds >= 0 })
}
