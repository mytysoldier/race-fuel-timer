import CoreLocation

// 試験用の仮閾値。実際の走行データでの誤判定率は未検証。
enum RouteGapProbe {
    static func analyze(_ locations: [CLLocation]) -> (points: [CLLocationCoordinate2D], breakIndices: Set<Int>) {
        var points: [CLLocationCoordinate2D] = []
        var breaks: Set<Int> = []
        var previous: CLLocation?
        for location in locations {
            guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0 else {
                previous = nil
                continue
            }
            if let previous {
                let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
                let distance = location.distance(from: previous)
                if seconds <= 0 || (distance > 100 && distance / seconds > 12) || (seconds > 120 && distance > 50) {
                    breaks.insert(points.count)
                }
            } else if !points.isEmpty {
                breaks.insert(points.count)
            }
            points.append(location.coordinate)
            previous = location
        }
        return (points, breaks)
    }
}
