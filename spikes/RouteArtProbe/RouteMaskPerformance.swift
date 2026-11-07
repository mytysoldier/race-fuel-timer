import CoreLocation
import Foundation

// 架空データを使う試作専用の測定。HealthKitやファイルにはアクセスしない。
enum RouteMaskPerformance {
    struct Result: Sendable {
        let segmentCount: Int
        let mode: String
        let medianSeconds: Double
        let remainingPoints: Int
    }

    static func run() -> [Result] {
        let pointCount = 6_050
        var results: [Result] = []
        for segmentLength in [6_050, 605, 60] {
            let points = (0..<pointCount).map { index in
                CLLocationCoordinate2D(latitude: Double(index / segmentLength) * 0.01,
                                       longitude: Double(index % segmentLength) * 0.0001)
            }
            let breaks = Set(stride(from: segmentLength, to: pointCount, by: segmentLength))
            for centers in [RoutePrivacyProbe.Centers.overall, .eachSegment] {
                var durations: [Double] = []
                var remaining = 0
                for _ in 0..<3 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let masked = RoutePrivacyProbe.mask(points, breaks: breaks, radius: 200, centers: centers)
                    durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
                    remaining = masked.points.count
                }
                results.append(Result(segmentCount: breaks.count + 1,
                                      mode: centers == .overall ? "全体" : "各区間",
                                      medianSeconds: durations.sorted()[1], remainingPoints: remaining))
            }
        }
        return results
    }
}
