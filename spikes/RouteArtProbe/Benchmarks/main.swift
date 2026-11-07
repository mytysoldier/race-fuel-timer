import CoreLocation
import Foundation

// 架空の点だけを使う単発の比較。実際のルートや端末性能を代表しない。
let pointCount = 6_050
for segmentLength in [6_050, 605, 60] {
    let points = (0..<pointCount).map { index in
        CLLocationCoordinate2D(
            latitude: Double(index / segmentLength) * 0.01,
            longitude: Double(index % segmentLength) * 0.0001
        )
    }
    let breaks = Set(stride(from: segmentLength, to: pointCount, by: segmentLength))
    for centers in [RoutePrivacyProbe.Centers.overall, .eachSegment] {
        var durations: [Double] = []
        var remaining = 0
        for _ in 0..<3 {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = RoutePrivacyProbe.mask(points, breaks: breaks, radius: 200, centers: centers)
            durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
            remaining = result.points.count
        }
        let median = durations.sorted()[1]
        print("点数: \(pointCount), 区間: \(breaks.count + 1), 方式: \(centers), 中央値: \(String(format: "%.3f", median))秒, 残る点: \(remaining)")
    }
}
