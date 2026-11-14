import CoreLocation
import Testing
@testable import RoutePrivacyProbe

@Test func 日付変更線を越える近接点は狭い経度範囲で順序を保つ() {
    // Arrange
    let points = [179.9, -179.9, -179.8].map { CLLocationCoordinate2D(latitude: 0, longitude: $0) }

    // Act
    let longitudes = RoutePrivacyProbe.drawingLongitudes(points)

    // Assert
    #expect(longitudes.count == points.count)
    #expect(abs((longitudes[1] - longitudes[0]) - 0.2) < 0.000001)
    #expect(abs((longitudes[2] - longitudes[1]) - 0.1) < 0.000001)
}

@Test func 日付変更線を越えない点も相対的な経度差を保つ() {
    // Arrange
    let points = [139.7, 139.6, 139.8].map { CLLocationCoordinate2D(latitude: 35, longitude: $0) }

    // Act
    let longitudes = RoutePrivacyProbe.drawingLongitudes(points)

    // Assert
    #expect(abs((longitudes[1] - longitudes[0]) + 0.1) < 0.000001)
    #expect(abs((longitudes[2] - longitudes[0]) - 0.1) < 0.000001)
}

@Test func 東西180度は同じ経度として描画する() {
    // Arrange
    let points = [180.0, -180.0].map { CLLocationCoordinate2D(latitude: 0, longitude: $0) }

    // Act
    let longitudes = RoutePrivacyProbe.drawingLongitudes(points)

    // Assert
    #expect(longitudes.count == 2)
    #expect(longitudes[0] == longitudes[1])
}
