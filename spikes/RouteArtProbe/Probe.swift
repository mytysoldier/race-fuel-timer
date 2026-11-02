import SwiftUI
import HealthKit
import CoreLocation
import Photos
import UIKit

@main struct RouteArtProbe: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let backgrounds = ["sunrise", "forest", "coast-generated"]
    @State private var background = ["sunrise", "forest", "coast-generated"].randomElement() ?? "sunrise"
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var breakIndices: Set<Int> = []
    @State private var status = "架空のルートで表示中"
    @State private var selectedWorkout: HKWorkout?
    @State private var lineColor = "白"
    @State private var lineStyle = "実線"
    @State private var hideEndpoints = false
    @State private var shareImage: ExportImage?
    @State private var exportMessage = ""
    @State private var hasRequestedRoute = false
    @State private var needsRefresh = false
    @State private var requestID = UUID()
    @State private var routeObserver: HKAnchoredObjectQuery?
    @State private var observerID = UUID()
#if targetEnvironment(simulator)
    @State private var pendingWorkout: HKWorkout?
    @State private var storageMessage = ""
    @State private var formatMessage = ""
    @State private var jpegPreview: UIImage?
#endif
    private var routeColor: Color {
        switch lineColor { case "オレンジ": return .orange; case "水色": return .cyan; default: return .white }
    }
    private var artworkRoute: (points: [CLLocationCoordinate2D], breaks: Set<Int>) {
        let input = hasRequestedRoute ? points : sample
        let originalBreaks = hasRequestedRoute ? breakIndices : Set<Int>()
        return hideEndpoints ? RoutePrivacyProbe.mask(input, breaks: originalBreaks, radius: 200) : (input, originalBreaks)
    }
    private var hasVisibleLine: Bool {
        let route = artworkRoute
        return route.points.count > 1 && (1..<route.points.count).contains { !route.breaks.contains($0) }
    }
    private let store = HKHealthStore()
    private let sample = [(0.1,0.3),(0.2,0.18),(0.42,0.12),(0.52,0.3),(0.7,0.25),(0.88,0.42),(0.75,0.58),(0.82,0.78),(0.58,0.9),(0.4,0.7),(0.21,0.82),(0.1,0.6),(0.1,0.3)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    artwork.aspectRatio(4.0 / 5.0, contentMode: .fit)
                    Text(status).font(.footnote)
                    Button("背景を変更") {
                        let index = backgrounds.firstIndex(of: background) ?? 0
                        background = backgrounds[(index + 1) % backgrounds.count]
                    }.buttonStyle(.borderedProminent)
                    Text("背景は変更できます").font(.caption).foregroundStyle(.secondary)
                    Picker("線の色", selection: $lineColor) {
                        Text("白").tag("白"); Text("オレンジ").tag("オレンジ"); Text("水色").tag("水色")
                    }.pickerStyle(.segmented)
                    Picker("線の見た目", selection: $lineStyle) {
                        Text("実線").tag("実線"); Text("点線").tag("点線"); Text("太線").tag("太線"); Text("光る線").tag("光る線")
                    }.pickerStyle(.segmented)
                    Toggle("開始・終了地点の周囲を隠す（検証用・約200m）", isOn: $hideEndpoints)
                    if hideEndpoints && !hasVisibleLine {
                        Text("表示できるルートが残りません。設定を変更してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("一部を隠しても、ルートの形などから場所が推測される可能性があります。保存・共有前に画像をご確認ください。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("写真に保存") { saveImage() }.buttonStyle(.borderedProminent)
                        Button("共有") { prepareShare() }.buttonStyle(.bordered)
                    }
                    .disabled(!hasVisibleLine)
                    if !exportMessage.isEmpty { Text(exportMessage).font(.caption) }
                    Button("HealthKitのランを読み込む") { read() }.buttonStyle(.bordered)
#if targetEnvironment(simulator)
                    Button("検証用にアプリ内へ保存") { saveProbeArtwork() }
                        .buttonStyle(.bordered).disabled(!hasVisibleLine)
                    NavigationLink("検証用の保存作品を見る") {
                        ProbeSavedArtworks()
                    }
                    if !storageMessage.isEmpty { Text(storageMessage).font(.caption) }
                    Button("検証用にPNGとJPEGを比較") { compareImageFormats() }
                        .buttonStyle(.bordered).disabled(!hasVisibleLine)
                    if !formatMessage.isEmpty { Text(formatMessage).font(.caption) }
                    if let jpegPreview {
                        Text("JPEG 0.85 の再読み込み画像（検証用）").font(.caption)
                        Image(uiImage: jpegPreview).resizable().scaledToFit()
                    }
                    Button("架空ルート付きランを追加") { seed(.normal) }.buttonStyle(.bordered)
                    Button("2本の架空ルート付きランを追加") { seed(.multiple) }.buttonStyle(.bordered)
                    Button("離れた2区間の架空ランを追加") { seed(.separated) }.buttonStyle(.bordered)
                    Button("ルートなしランを追加") { seed(.noRoute) }.buttonStyle(.bordered)
                    Button("直前のルートなしランにルートを追加") { addDelayedRoute() }
                        .buttonStyle(.bordered).disabled(pendingWorkout == nil)
                    Button("長い架空ルートを追加") { seed(.long) }.buttonStyle(.bordered)
                    Button("欠損のある架空ルートを追加") { seed(.gap) }.buttonStyle(.bordered)
#endif
                    Text("検証用：背景はサンプルです。HealthKit未読込時のルートも架空です。") .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("ルートアート検証")
                .sheet(item: $shareImage) { item in
                    ShareSheet(image: item.image) { completed in
                        exportMessage = completed ? "共有先での処理が完了しました" : "共有は完了していません"
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && hasRequestedRoute {
#if targetEnvironment(simulator)
                jpegPreview = nil; formatMessage = ""
#endif
                requestID = UUID()
                stopRouteObserver()
                points = []; breakIndices = []; selectedWorkout = nil
                status = "ルートを再確認します"
                needsRefresh = true
            } else if phase == .active && needsRefresh {
                needsRefresh = false
                read()
            }
        }
    }
    private var artwork: some View {
        GeometryReader { geometry in
                        ZStack {
                            if let path = Bundle.main.path(forResource: background, ofType: "jpg", inDirectory: "Images"), let image = UIImage(contentsOfFile: path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            } else { Color.gray }
                            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.2), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                            VStack(spacing: 0) {
                                ZStack {
                                    let shape = RouteShape(points: artworkRoute.points, smoothSample: !hasRequestedRoute && !hideEndpoints, breakIndices: artworkRoute.breaks)
                                    let width: CGFloat = lineStyle == "太線" ? 6 : 3
                                    let dash: [CGFloat] = lineStyle == "点線" ? [3, 8] : []
                                    shape.stroke(.black.opacity(0.8), style: StrokeStyle(lineWidth: width + 3, lineCap: .round, lineJoin: .round, dash: dash))
                                    shape.stroke(routeColor, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
                                        .shadow(color: lineStyle == "光る線" ? routeColor.opacity(0.9) : .black.opacity(0.65), radius: lineStyle == "光る線" ? 7 : 3)
                                }
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
                                    } else if !hasRequestedRoute { Text("サンプル").font(.caption) }
                                }.foregroundStyle(.white).padding(.bottom, 24)
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @MainActor private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: artwork.frame(width: 360, height: 450))
        renderer.scale = 3
        return renderer.uiImage
    }

    @MainActor private func saveImage() {
        guard let image = renderImage() else { exportMessage = "画像を作成できませんでした"; return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { exportMessage = "写真への追加が許可されていません" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                DispatchQueue.main.async { exportMessage = success ? "写真に保存しました" : "写真に保存できませんでした" }
            }
        }
    }

    @MainActor private func prepareShare() {
        guard let image = renderImage() else { exportMessage = "画像を作成できませんでした"; return }
        exportMessage = ""
        shareImage = ExportImage(image: image)
    }

    func authorize(write: Bool, isCurrent: @escaping () -> Bool = { true }, completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { if isCurrent() { status = "HealthKitを利用できません"; completion(false) } }
            return
        }
        let workout = HKObjectType.workoutType(), route = HKSeriesType.workoutRoute()
        store.requestAuthorization(toShare: write ? [workout, route] : [], read: [workout, route]) { ok, error in
            DispatchQueue.main.async {
                guard isCurrent() else { return }
                if let error { status = "権限要求エラー: \(error.localizedDescription)" }
                completion(ok && error == nil)
            }
        }
    }
    func read() {
#if targetEnvironment(simulator)
        jpegPreview = nil; formatMessage = ""
#endif
        hasRequestedRoute = true
        let currentRequest = UUID()
        requestID = currentRequest
        points = []; breakIndices = []; selectedWorkout = nil
        exportMessage = ""
        status = "ルートを読み込み中"
        authorize(write: false, isCurrent: { currentRequest == requestID }) { ok in
            guard currentRequest == requestID, ok else { return }
            startRouteObserver()
            let predicate = HKQuery.predicateForWorkouts(with: .running)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 30, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                DispatchQueue.main.async {
                    guard currentRequest == requestID else { return }
                    guard let workouts = samples as? [HKWorkout], error == nil else { status = "ランの読み込みに失敗"; return }
                    findRoute(workouts, index: 0, request: currentRequest)
                }
            }
            store.execute(query)
        }
    }
    // 追加・削除を検知したら最新のランを探し直す、検証用の単純な方式。
    func startRouteObserver() {
        guard routeObserver == nil else { return }
        let currentObserver = UUID()
        observerID = currentObserver
        let query = HKAnchoredObjectQuery(type: HKSeriesType.workoutRoute(), predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { _, _, _, _, error in
            DispatchQueue.main.async {
                guard currentObserver == observerID else { return }
                if error != nil { status = "ルート変更の監視に失敗しました"; return }
                // 初回スナップショットと検索の間の変更も取りこぼさないよう再検索する。
                read()
            }
        }
        query.updateHandler = { _, added, deleted, _, error in
            DispatchQueue.main.async {
                guard currentObserver == observerID else { return }
                if error != nil { status = "ルート変更の監視に失敗しました"; return }
                if !(added ?? []).isEmpty || !(deleted ?? []).isEmpty { read() }
            }
        }
        routeObserver = query
        store.execute(query)
    }
    func stopRouteObserver() {
        observerID = UUID()
        if let routeObserver { store.stop(routeObserver) }
        routeObserver = nil
    }
    func findRoute(_ workouts: [HKWorkout], index: Int, request: UUID) {
        guard request == requestID else { return }
        guard index < workouts.count else { status = "ルート付きランが見つかりません。アクセス設定や記録を確認してください"; return }
        let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workouts[index]), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            DispatchQueue.main.async {
            guard request == requestID else { return }
            if error != nil { status = "ルートの読み込みに失敗"; return }
            guard let routes = samples as? [HKWorkoutRoute], !routes.isEmpty else { findRoute(workouts, index: index + 1, request: request); return }
            let ordered = routes.sorted { a, b in
                a.startDate == b.startDate ? a.uuid.uuidString < b.uuid.uuidString : a.startDate < b.startDate
            }
            readRoutes(ordered, index: 0, workout: workouts[index], request: request, accumulated: [], breaks: [])
            }
        }
        store.execute(query)
    }
    // ルートごとに全バッチを読み、異なるルート間は線で結ばない。
    func readRoutes(_ routes: [HKWorkoutRoute], index: Int, workout: HKWorkout, request: UUID, accumulated: [CLLocationCoordinate2D], breaks: Set<Int>) {
        guard request == requestID else { return }
        guard index < routes.count else {
            points = accumulated; breakIndices = breaks; selectedWorkout = workout
            status = "HealthKitから \(accumulated.count) 点を読み込み、\(breaks.count) 箇所を分断候補として表示"
            return
        }
        var locations: [CLLocation] = []
        let query = HKWorkoutRouteQuery(route: routes[index]) { _, batch, done, error in
            DispatchQueue.main.async {
                guard request == requestID else { return }
                if error != nil { status = "位置データの読み込みに失敗"; return }
                locations.append(contentsOf: batch ?? [])
                guard done else { return }
                let result = RouteGapProbe.analyze(locations)
                var nextBreaks = breaks
                if !accumulated.isEmpty && !result.points.isEmpty { nextBreaks.insert(accumulated.count) }
                nextBreaks.formUnion(result.breakIndices.map { $0 + accumulated.count })
                readRoutes(routes, index: index + 1, workout: workout, request: request, accumulated: accumulated + result.points, breaks: nextBreaks)
            }
        }
        store.execute(query)
    }
#if targetEnvironment(simulator)
    @MainActor private func compareImageFormats() {
        jpegPreview = nil
        guard let image = renderImage(), let png = image.pngData(),
              let jpeg = image.jpegData(compressionQuality: 0.85),
              let preview = UIImage(data: jpeg) else {
            formatMessage = "画像を変換できませんでした"
            return
        }
        jpegPreview = preview
        formatMessage = "PNG: \(png.count) バイト / JPEG 0.85: \(jpeg.count) バイト"
    }
    @MainActor private func saveProbeArtwork() {
        guard let data = renderImage()?.pngData() else { storageMessage = "画像を作成できませんでした"; return }
        do {
            let directory = try ProbeSavedArtworks.directory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(UUID().uuidString).png"), options: .atomic)
            storageMessage = "検証用画像を保存しました（\(data.count) バイト）"
        } catch {
            storageMessage = "検証用画像を保存できませんでした"
        }
    }
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
    enum Fixture { case normal, noRoute, long, gap, multiple, separated }
    func seed(_ fixture: Fixture) {
        authorize(write: true) { ok in
            guard ok else { return }
            let end = Date(), start = end.addingTimeInterval(-1800)
            let workout = HKWorkout(activityType: .running, start: start, end: end)
            store.save(workout) { success, error in
                guard success else { DispatchQueue.main.async { status = "架空ランの保存失敗: \(error?.localizedDescription ?? "不明")" }; return }
                if fixture == .noRoute {
                    DispatchQueue.main.async {
                        pendingWorkout = workout
                        status = "ルートなしランを追加しました。読み込みを押してください"
                    }
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
                let firstPositions = fixture == .separated ? Array(positions.prefix(61)) : positions
                let secondPositions: [CLLocation] = fixture == .separated ? positions.suffix(60).map { location in
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude + 0.02), altitude: location.altitude, horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy, timestamp: location.timestamp)
                } : positions.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
                builder.insertRouteData(firstPositions) { success, error in
                    guard success else { DispatchQueue.main.async { status = "架空ルートの保存失敗: \(error?.localizedDescription ?? "不明")" }; return }
                    builder.finishRoute(with: workout, metadata: nil) { _, error in
                        if let error {
                            DispatchQueue.main.async { status = "ルート作成失敗: \(error.localizedDescription)" }
                        } else if fixture == .multiple || fixture == .separated {
                            addSecondFixtureRoute(to: workout, positions: secondPositions)
                        } else {
                            DispatchQueue.main.async { status = "架空ランを追加しました。読み込みを押してください" }
                        }
                    }
                }
            }
        }
    }
    // 最初のルート保存後に同じランへ別のルートを追加する。
    func addSecondFixtureRoute(to workout: HKWorkout, positions: [CLLocation]) {
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        builder.insertRouteData(positions) { success, error in
            guard success else {
                DispatchQueue.main.async { status = "2本目のルート保存失敗: \(error?.localizedDescription ?? "不明")" }
                return
            }
            builder.finishRoute(with: workout, metadata: nil) { route, error in
                DispatchQueue.main.async {
                    if route != nil && error == nil { status = "2本の架空ルートを追加しました。読み込みを押してください" }
                    else { status = "2本目のルート作成失敗: \(error?.localizedDescription ?? "不明")" }
                }
            }
        }
    }
    func addDelayedRoute() {
        guard let workout = pendingWorkout else { return }
        pendingWorkout = nil
        let coordinates = denseSample().enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        let positions = coordinates.enumerated().map { index, point in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35 + point.latitude * 0.01, longitude: 139 + point.longitude * 0.01), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: workout.startDate.addingTimeInterval(Double(index) * workout.duration / Double(max(coordinates.count, 1))))
        }
        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        builder.insertRouteData(positions) { success, error in
            guard success else {
                DispatchQueue.main.async { pendingWorkout = workout; status = "架空ルートの保存失敗: \(error?.localizedDescription ?? "不明")" }
                return
            }
            builder.finishRoute(with: workout, metadata: nil) { _, error in
                DispatchQueue.main.async {
                    if let error { pendingWorkout = workout; status = "ルート作成失敗: \(error.localizedDescription)" }
                    else { status = "後からルートを追加しました。読み込みを押してください" }
                }
            }
        }
    }
#endif
}

#if targetEnvironment(simulator)
struct ProbeSavedArtworks: View {
    @State private var images: [URL] = []
    @State private var message = "読み込み中"
    var body: some View {
        ScrollView {
            VStack {
                Text(message)
                ForEach(images, id: \.self) { url in
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Text("保存画像を読み込めません: \(url.lastPathComponent)")
                    }
                }
            }.padding()
        }.navigationTitle("検証用の保存作品").onAppear { load() }
    }
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RouteArtProbeImages", isDirectory: true)
    }
    private func load() {
        do {
            let directory = try Self.directory()
            guard FileManager.default.fileExists(atPath: directory.path) else { images = []; message = "保存作品はありません"; return }
            images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            message = images.isEmpty ? "保存作品はありません" : "保存作品: \(images.count) 件"
        } catch {
            images = []; message = "保存作品を読み込めませんでした"
        }
    }
}
#endif

struct RouteShape: Shape {
    let points: [CLLocationCoordinate2D]
    let smoothSample: Bool
    let breakIndices: Set<Int>
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
            for index in 1..<projected.count {
                if breakIndices.contains(index) { path.move(to: projected[index]) } else { path.addLine(to: projected[index]) }
            }
        }
        return path
    }
}

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

struct ExportImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    let onComplete: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// 評価用の保守的な試案。開始・終了点から半径内の点と、円を横切る線分を描かない。
// 位置特定や、他の訪問による露出を完全に防ぐものではない。
enum RoutePrivacyProbe {
    static func mask(_ points: [CLLocationCoordinate2D], breaks: Set<Int>, radius: CLLocationDistance) -> (points: [CLLocationCoordinate2D], breaks: Set<Int>) {
        guard points.count > 1, radius > 0 else { return ([], []) }
        let centers = [points[0], points[points.count - 1]]
        func location(_ point: CLLocationCoordinate2D) -> CLLocation { CLLocation(latitude: point.latitude, longitude: point.longitude) }
        func inside(_ point: CLLocationCoordinate2D) -> Bool {
            centers.contains { location(point).distance(from: location($0)) <= radius }
        }
        // 三角不等式で円への到達があり得る線分も除く。安全側に広く隠れる場合がある。
        func mightCross(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            let segment = location(a).distance(from: location(b))
            return centers.contains { center in
                let c = location(center)
                return max(0, (c.distance(from: location(a)) + c.distance(from: location(b)) - segment) / 2) <= radius
            }
        }
        var output: [CLLocationCoordinate2D] = []
        var outputBreaks: Set<Int> = []
        var previousIndex: Int?
        for (index, point) in points.enumerated() {
            guard CLLocationCoordinate2DIsValid(point), !inside(point) else { previousIndex = nil; continue }
            if !output.isEmpty {
                if let previousIndex, previousIndex + 1 == index, !breaks.contains(index), !mightCross(points[previousIndex], point) {
                    // この線分は両端の保護範囲に入らない。
                } else { outputBreaks.insert(output.count) }
            }
            output.append(point)
            previousIndex = index
        }
        return (output, outputBreaks)
    }
}
