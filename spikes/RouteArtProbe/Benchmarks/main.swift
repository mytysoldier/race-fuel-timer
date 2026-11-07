import Foundation

for result in RouteMaskPerformance.run() {
    print("点数: 6050, 区間: \(result.segmentCount), 方式: \(result.mode), 中央値: \(String(format: "%.3f", result.medianSeconds))秒, 残る点: \(result.remainingPoints)")
}
