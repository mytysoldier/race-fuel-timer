import CoreLocation

// 評価用の保守的な試案。開始・終了点から半径内の点と、円を横切る線分を描かない。
// 位置特定や、他の訪問による露出を完全に防ぐものではない。
enum RoutePrivacyProbe {
    enum Centers { case overall, eachSegment }

    // 日付変更線を含む点群も、最も狭い経度範囲に収める。描画用で元の座標は変更しない。
    static func drawingLongitudes(_ points: [CLLocationCoordinate2D]) -> [Double] {
        guard !points.isEmpty else { return [] }
        let normalized = points.map { point in
            let value = point.longitude.truncatingRemainder(dividingBy: 360)
            return value < 0 ? value + 360 : value
        }
        let ordered = normalized.sorted()
        var largestGap = -Double.infinity
        var start = ordered[0]
        for index in ordered.indices {
            let next = index + 1 < ordered.count ? ordered[index + 1] : ordered[0] + 360
            let gap = next - ordered[index]
            if gap > largestGap {
                largestGap = gap
                start = index + 1 < ordered.count ? ordered[index + 1] : ordered[0]
            }
        }
        return normalized.map { $0 < start ? $0 + 360 : $0 }
    }

    static func hasDrawableLine(_ points: [CLLocationCoordinate2D], breaks: Set<Int>) -> Bool {
        guard points.count > 1 else { return false }
        return (1..<points.count).contains { index in
            let previous = points[index - 1], current = points[index]
            return !breaks.contains(index)
                && CLLocationCoordinate2DIsValid(previous) && CLLocationCoordinate2DIsValid(current)
                && (previous.latitude != current.latitude || previous.longitude != current.longitude)
        }
    }

    static func mask(_ points: [CLLocationCoordinate2D], breaks: Set<Int>, radius: CLLocationDistance, centers: Centers = .overall) -> (points: [CLLocationCoordinate2D], breaks: Set<Int>) {
        guard points.count > 1, radius > 0 else { return ([], []) }
        let starts = breaks.filter { $0 > 0 && $0 < points.count }.sorted()
        let centerIndices: [Int]
        switch centers {
        case .overall: centerIndices = [0, points.count - 1]
        case .eachSegment: centerIndices = [0, points.count - 1] + starts.flatMap { [$0 - 1, $0] }
        }
        let centerPoints = centerIndices.map { points[$0] }
        guard centerPoints.allSatisfy({ CLLocationCoordinate2DIsValid($0) }) else { return ([], []) }
        func location(_ point: CLLocationCoordinate2D) -> CLLocation { CLLocation(latitude: point.latitude, longitude: point.longitude) }
        let centerLocations = centerPoints.map(location)
        func inside(_ point: CLLocation) -> Bool {
            centerLocations.contains { point.distance(from: $0) <= radius }
        }
        // 三角不等式で円への到達があり得る線分も除く。安全側に広く隠れる場合がある。
        func mightCross(_ a: CLLocation, _ b: CLLocation) -> Bool {
            let segment = a.distance(from: b)
            return centerLocations.contains { center in
                max(0, (center.distance(from: a) + center.distance(from: b) - segment) / 2) <= radius
            }
        }
        var output: [CLLocationCoordinate2D] = []
        var outputBreaks: Set<Int> = []
        var previousIndex: Int?
        var previousLocation: CLLocation?
        for (index, point) in points.enumerated() {
            guard CLLocationCoordinate2DIsValid(point) else { previousIndex = nil; previousLocation = nil; continue }
            let currentLocation = location(point)
            guard !inside(currentLocation) else { previousIndex = nil; previousLocation = nil; continue }
            if !output.isEmpty {
                if let previousIndex, let previousLocation, previousIndex + 1 == index, !breaks.contains(index), !mightCross(previousLocation, currentLocation) {
                    // この線分は両端の保護範囲に入らない。
                } else { outputBreaks.insert(output.count) }
            }
            output.append(point)
            previousIndex = index
            previousLocation = currentLocation
        }
        return (output, outputBreaks)
    }
}
