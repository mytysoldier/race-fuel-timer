import CoreLocation
import Testing
@testable import RoutePrivacyProbe

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
