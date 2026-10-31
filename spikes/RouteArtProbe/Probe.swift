import SwiftUI
import HealthKit
import CoreLocation

@main struct RouteArtProbe: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @State private var background = ["sunrise", "forest"].randomElement() ?? "sunrise"
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var status = "架空のルートで表示中"
    @State private var selectedWorkout: HKWorkout?
    private let store = HKHealthStore()
    private let sample = [(0.1,0.3),(0.2,0.18),(0.42,0.12),(0.52,0.3),(0.7,0.25),(0.88,0.42),(0.75,0.58),(0.82,0.78),(0.58,0.9),(0.4,0.7),(0.21,0.82),(0.1,0.6),(0.1,0.3)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GeometryReader { geometry in
                        ZStack {
                            if let path = Bundle.main.path(forResource: background, ofType: "jpg", inDirectory: "Images"), let image = UIImage(contentsOfFile: path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            } else { Color.gray }
                            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.2), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                            VStack(spacing: 0) {
                                RouteShape(points: points.isEmpty ? sample : points, smoothSample: points.isEmpty)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                    .shadow(color: .black.opacity(0.65), radius: 3)
                                    .padding(.horizontal, 25).padding(.vertical, 30)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                VStack(spacing: 7) {
                                    Text("YOUR RUN").font(.system(size: 11, weight: .semibold)).tracking(3)
                                    if let workout = selectedWorkout, let distance = workout.totalDistance?.doubleValue(for: .meter()), distance > 0 {
                                        Text(String(format: "%.2f km", distance / 1000)).font(.system(size: 38, weight: .medium, design: .serif))
                                    } else { Text("走った軌跡").font(.system(size: 28, weight: .medium, design: .serif)) }
                                    if let workout = selectedWorkout {
                                        Text(workout.endDate, format: .dateTime.year().month().day()).font(.caption)
                                        Text("時間 \(Int(workout.duration / 60))分").font(.caption)
                                    } else { Text("サンプル").font(.caption) }
                                }.foregroundStyle(.white).padding(.bottom, 24)
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                    }.aspectRatio(4.0 / 5.0, contentMode: .fit)
                    Text(status).font(.footnote)
                    Button("背景を変更") { background = background == "sunrise" ? "forest" : "sunrise" }.buttonStyle(.borderedProminent)
                    Text("背景は変更できます").font(.caption).foregroundStyle(.secondary)
                    Button("HealthKitのランを読み込む") { read() }.buttonStyle(.bordered)
#if targetEnvironment(simulator)
                    Button("架空ルート付きランを追加") { seed(.normal) }.buttonStyle(.bordered)
                    Button("ルートなしランを追加") { seed(.noRoute) }.buttonStyle(.bordered)
                    Button("長い架空ルートを追加") { seed(.long) }.buttonStyle(.bordered)
                    Button("欠損のある架空ルートを追加") { seed(.gap) }.buttonStyle(.bordered)
#endif
                    Text("検証用：写真とルートはサンプルです。保存・共有は未実装です。") .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("ルートアート検証")
        }
    }
    func authorize(write: Bool, completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { DispatchQueue.main.async { status = "HealthKitを利用できません" }; return }
        let workout = HKObjectType.workoutType(), route = HKSeriesType.workoutRoute()
        store.requestAuthorization(toShare: write ? [workout, route] : [], read: [workout, route]) { ok, error in
            DispatchQueue.main.async { if let error { status = "権限要求エラー: \(error.localizedDescription)" }; completion(ok && error == nil) }
        }
    }
    func read() {
        authorize(write: false) { ok in
            guard ok else { return }
            let predicate = HKQuery.predicateForWorkouts(with: .running)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 30, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else { DispatchQueue.main.async { status = "ランの読み込みに失敗" }; return }
                findRoute(workouts, index: 0)
            }
            store.execute(query)
        }
    }
    func findRoute(_ workouts: [HKWorkout], index: Int) {
        guard index < workouts.count else { DispatchQueue.main.async { points = []; selectedWorkout = nil; status = "ルート付きランが見つかりません。アクセス設定や記録を確認してください" }; return }
        let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workouts[index]), limit: 1, sortDescriptors: nil) { _, samples, error in
            if error != nil { DispatchQueue.main.async { status = "ルートの読み込みに失敗" }; return }
            guard let route = samples?.first as? HKWorkoutRoute else { findRoute(workouts, index: index + 1); return }
            var locations: [CLLocation] = []
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if error != nil { DispatchQueue.main.async { status = "位置データの読み込みに失敗" }; return }
                locations.append(contentsOf: batch ?? [])
                if done { let result = locations.map(\.coordinate); DispatchQueue.main.async { points = result; selectedWorkout = workouts[index]; status = "HealthKitから \(result.count) 点を読み込みました" } }
            }
            store.execute(routeQuery)
        }
        store.execute(query)
    }
#if targetEnvironment(simulator)
    // 架空データを密にして、実際のGPSのような連続した点を検証する。
    func denseSample() -> [CLLocationCoordinate2D] {
        (0..<(sample.count - 1)).flatMap { index -> [CLLocationCoordinate2D] in
            let p0 = sample[max(index - 1, 0)], p1 = sample[index]
            let p2 = sample[index + 1], p3 = sample[min(index + 2, sample.count - 1)]
            func interpolate(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
                0.5 * ((2 * b) + (-a + c) * t + (2*a - 5*b + 4*c - d) * t*t + (-a + 3*b - 3*c + d) * t*t*t)
            }
            return (0..<10).map { step in
                let t = Double(step) / 10
                return CLLocationCoordinate2D(latitude: interpolate(p0.latitude, p1.latitude, p2.latitude, p3.latitude, t), longitude: interpolate(p0.longitude, p1.longitude, p2.longitude, p3.longitude, t))
            }
        } + [sample.last!]
    }
    enum Fixture { case normal, noRoute, long, gap }
    func seed(_ fixture: Fixture) {
        authorize(write: true) { ok in
            guard ok else { return }
            let end = Date(), start = end.addingTimeInterval(-1800)
            let workout = HKWorkout(activityType: .running, start: start, end: end)
            store.save(workout) { success, error in
                guard success else { DispatchQueue.main.async { status = "架空ランの保存失敗: \(error?.localizedDescription ?? "不明")" }; return }
                if fixture == .noRoute {
                    DispatchQueue.main.async { status = "ルートなしランを追加しました。読み込みを押してください" }
                    return
                }
                let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
                let source = denseSample()
                let coordinates: [CLLocationCoordinate2D]
                if fixture == .long {
                    coordinates = (0..<50).flatMap { lap in
                        source.map { CLLocationCoordinate2D(latitude: $0.latitude + Double(lap) * 0.02, longitude: $0.longitude) }
                    }
                } else if fixture == .gap {
                    coordinates = Array(source.prefix(40)) + source.suffix(40).map {
                        CLLocationCoordinate2D(latitude: $0.latitude + 2, longitude: $0.longitude + 2)
                    }
                } else {
                    coordinates = source
                }
                let positions = coordinates.enumerated().map { i, p in CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35 + p.latitude * 0.01, longitude: 139 + p.longitude * 0.01), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(Double(i) * 1800 / Double(max(coordinates.count, 1)))) }
                builder.insertRouteData(positions) { success, error in
                    guard success else { DispatchQueue.main.async { status = "架空ルートの保存失敗: \(error?.localizedDescription ?? "不明")" }; return }
                    builder.finishRoute(with: workout, metadata: nil) { _, error in DispatchQueue.main.async { status = error == nil ? "架空ランを追加しました。読み込みを押してください" : "ルート作成失敗: \(error!.localizedDescription)" } }
                }
            }
        }
    }
#endif
}

struct RouteShape: Shape {
    let points: [CLLocationCoordinate2D]
    let smoothSample: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let valid = points.filter { CLLocationCoordinate2DIsValid($0) }
        guard valid.count > 1, let minLat = valid.map(\.latitude).min(), let maxLat = valid.map(\.latitude).max(), let minLon = valid.map(\.longitude).min(), let maxLon = valid.map(\.longitude).max() else { return path }
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = max((maxLon - minLon) * lonScale, 0.000001), height = max(maxLat - minLat, 0.000001)
        let scale = min(rect.width / width, rect.height / height)
        let xOffset = (rect.width - width * scale) / 2, yOffset = (rect.height - height * scale) / 2
        let projected = valid.map { point in
            CGPoint(x: xOffset + (point.longitude - minLon) * lonScale * scale, y: yOffset + (maxLat - point.latitude) * scale)
        }
        path.move(to: projected[0])
        if smoothSample {
            for index in 1..<projected.count {
                let previous = projected[index - 1], current = projected[index]
                let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: midpoint, control: previous)
            }
            path.addLine(to: projected[projected.count - 1])
        } else {
            for point in projected.dropFirst() { path.addLine(to: point) }
        }
        return path
    }
}
